part of '../show_system_francais.dart';

/// Side drawers and bottom panels of the drawing page.
extension _WindowViewDrawers on _WindowViewState {
  void _switchToBottomTab(int id) {
    if (!mounted) return;
    _setViewState(() {
      _isBottomPanelExpanded = true;
      if (id == 6) {
        _isShutterSelected = true;
        _activeShutterTab = 0;
        _previousSelectionKey = _currentSelectionKey();
      } else {
        _isShutterSelected = false;
        _activeBottomTab = id;
        _handleCandidates = null;
        if (id == 1) {
          if (widget.model.frames.isNotEmpty &&
              widget.model.selectedFrame == null) {
            widget.model.selectFrameByIndex(0);
          }
        } else if (widget.model.selectedZone == null &&
            widget.model.zones.isNotEmpty &&
            id != 3) {
          widget.model.selection = SelectionInfo.zone(
            widget.model.zones.first.id,
          );
        }
        _previousSelectionKey = _currentSelectionKey();
      }
    });
    // Loading starts its own state update. Keep it outside the tab's setState
    // so the first click works without a nested state change.
    if (id == 6) unawaited(_loadShutterOptions());
  }

  /// On Windows Flutter excludes a mouse from drag scrolling by default.
  /// Both drawing drawers contain horizontal option rows, so enable mouse and
  /// trackpad dragging here without changing the phone touch experience.
  ScrollBehavior _drawerScrollBehavior(
    BuildContext context, {
    bool scrollbars = true,
  }) {
    return ScrollConfiguration.of(context).copyWith(
      scrollbars: scrollbars,
      dragDevices: const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
        PointerDeviceKind.unknown,
      },
    );
  }

  /// Automatically scrolls the drawer downwards so newly opened items or expanded
  /// options are smoothly revealed and fully visible to the user.
  void _autoScrollDrawer({
    BuildContext? targetContext,
    double? additionalDelta,
  }) {
    if (targetContext != null && targetContext.mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !targetContext.mounted) return;
        Scrollable.ensureVisible(
          targetContext,
          duration: const Duration(milliseconds: 320),
          curve: Curves.easeOutCubic,
          alignment: 0.95,
          alignmentPolicy: ScrollPositionAlignmentPolicy.keepVisibleAtEnd,
        );
      });
      return;
    }

    if (!_leftDrawerScrollController.hasClients) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_leftDrawerScrollController.hasClients) return;
      final position = _leftDrawerScrollController.position;
      final double delta = additionalDelta ?? 280.0;
      final target = (position.pixels + delta).clamp(
        0.0,
        position.maxScrollExtent,
      );
      if (target > position.pixels) {
        _leftDrawerScrollController.animateTo(
          target,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  Widget _buildLeftDrawerContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: _drawerScrollBehavior(context, scrollbars: false),
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final isDark = Theme.of(context).brightness == Brightness.dark;
          final lang = Provider.of<AppSettingsProvider>(context).language;
          final WindowZone? zone = widget.model.selectedZone;
          WindowZone? targetZone = zone;
          if (targetZone == null ||
              targetZone.content != ZoneContent.doubleSash) {
            for (var z in widget.model.zones) {
              if (z.content == ZoneContent.doubleSash) {
                targetZone = z;
                break;
              }
            }
          }

          Widget buildPaintbrushButton({
            required String label,
            required IconData icon,
            required GlassFinish finish,
            required GlassStructure structure,
          }) {
            final isSelected =
                _activePaintFinish == finish && _paintbrushSecondsLeft > 0;
            return Padding(
              padding: const EdgeInsets.only(right: 6),
              child: _ContentButton(
                label: label,
                icon: icon,
                selected: isSelected,
                onPressed: () {
                  _startPaintbrushMode(finish: finish, structure: structure);
                },
              ),
            );
          }

          // When a zone (or a cell inside it) is selected, its own glass is
          // the source of truth for this drawer.  Falling back to the whole
          // drawing is only appropriate before the user selects a target.
          // Otherwise changing a selected pane to a panneau would rebuild the
          // drawer from the neutral value and hide the panneau options.
          final GlassSpecification spec =
              zone?.getGlassForCell(widget.model.activeSubZone) ??
              _tempGlassSpec;
          final structure = spec.structure;
          final slidingJointSpecs = widget.model.zones
              .where((z) => z.content == ZoneContent.slidingSash)
              .expand((z) => [z.glass, ...z.cellGlassSpec.values])
              .toList();

          GlassSpecification fitDoubleGlassToParclose(
            GlassSpecification candidate,
          ) {
            if (candidate.structure != GlassStructure.double) {
              return candidate;
            }
            final zone = widget.model.selectedZone;
            final isSliding = zone != null
                ? zone.content == ZoneContent.slidingSash
                : widget.model.usesSlidingPrimaryProfiles;
            final suggested = widget.model
                .suggestedIntercallThicknessForDoubleGlass(
                  thicknessOuter:
                      candidate.thicknessOuter ?? kDefaultGlassPaneThickness,
                  thicknessInner:
                      candidate.thicknessInner ?? kDefaultGlassPaneThickness,
                  jointTwoSides: candidate.jointTwoSides,
                  sliding: isSliding,
                );
            if (suggested != null) {
              return candidate.copyWith(intercallThickness: suggested);
            }
            return candidate;
          }

          Widget? buildParcloseThicknessInfo() {
            final fitReport = widget.model.glazingFitReport;
            if (fitReport != null && fitReport.describes(spec)) {
              final fitColor = fitReport.valid
                  ? Colors.green.shade700
                  : Colors.red.shade700;
              return Container(
                margin: const EdgeInsets.only(top: 8),
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: fitColor.withValues(alpha: 0.10),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: fitColor.withValues(alpha: 0.35)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        fitReport.valid
                            ? Icons.check_circle_outline_rounded
                            : Icons.warning_amber_rounded,
                        color: fitColor,
                        size: 18,
                      ),
                    ),
                    const SizedBox(width: 7),
                    Expanded(
                      child: Text(
                        describeGlazingFit(fitReport, lang),
                        style: TextStyle(
                          color: fitColor,
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }
            if (zone?.content == ZoneContent.slidingSash ||
                (zone == null && widget.model.usesSlidingPrimaryProfiles)) {
              return _slidingGlassFitInfo(spec);
            }
            final usesParclose = widget.model.hasGlazingBeadForContext(
              sliding: false,
            );
            final maximum = widget.model.glazingCapacityForStructure(
              spec.structure,
              sliding: false,
            );
            if (maximum == null) {
              return null;
            }

            final glassTotal = spec.totalThickness(widget.model.allGlassCache);
            final fittedJointThickness = spec.fittedJoints.fold<double>(
              0.0,
              (sum, joint) =>
                  sum + (double.tryParse('${joint['thickness']}') ?? 0.0),
            );
            final jointVitrage = spec.fittedJoints.isNotEmpty
                ? fittedJointThickness
                : widget.model.isPVC
                ? 0.0
                : widget.model.selectedVitrageJointThickness(fallback: 2.0);
            final totalPack = glassTotal + jointVitrage;
            final remainingGap = maximum - totalPack;

            final isExact = remainingGap.abs() < 0.01;
            final isAbove = totalPack > maximum;
            final color =
                isExact || (remainingGap >= 2.0 && remainingGap <= 6.0)
                ? Colors.green.shade700
                : (isAbove ? Colors.red.shade700 : Colors.orange.shade800);
            final icon = isExact || (remainingGap >= 2.0 && remainingGap <= 6.0)
                ? Icons.check_circle_outline_rounded
                : Icons.warning_amber_rounded;

            String message;
            final hasOpeningSystem = widget.model.zones.any(
              (candidate) =>
                  candidate.content == ZoneContent.singleSash ||
                  candidate.content == ZoneContent.doubleSash,
            );
            final hasSlidingSystem = widget.model.zones.any(
              (candidate) => candidate.content == ZoneContent.slidingSash,
            );
            final seriesName = widget.model.activeSeries?.name ?? '';
            final openingPrefix = hasOpeningSystem && hasSlidingSystem
                ? (lang == AppLanguage.french
                    ? 'Système ouvrant ($seriesName) : '
                    : lang == AppLanguage.english
                    ? 'Opening system ($seriesName): '
                    : 'نظام الفتح ($seriesName): ')
                : '';
            final capacityLabel = usesParclose
                ? (lang == AppLanguage.french
                    ? 'la capacité parclose'
                    : lang == AppLanguage.english
                    ? 'glazing bead capacity'
                    : 'سعة البيركلوز')
                : (lang == AppLanguage.french
                    ? 'la capacité ouvrant'
                    : lang == AppLanguage.english
                    ? 'sash capacity'
                    : 'سعة الضلفة');
            final capacityLabelPlain = usesParclose
                ? (lang == AppLanguage.french
                    ? 'Capacité parclose'
                    : lang == AppLanguage.english
                    ? 'Glazing bead capacity'
                    : 'سعة البيركلوز')
                : (lang == AppLanguage.french
                    ? 'Capacité ouvrant'
                    : lang == AppLanguage.english
                    ? 'Sash capacity'
                    : 'سعة الضلفة');

            final unit = lang == AppLanguage.arabic ? 'مم' : 'mm';

            if (widget.model.isPVC || jointVitrage <= 0) {
              if (isExact) {
                message = lang == AppLanguage.french
                    ? '${openingPrefix}Épaisseur du vitrage conforme à $capacityLabel : ${glassTotal.toStringAsFixed(0)} $unit'
                    : lang == AppLanguage.english
                    ? '${openingPrefix}Glass thickness matches $capacityLabel: ${glassTotal.toStringAsFixed(0)} $unit'
                    : '${openingPrefix}سُمك الزجاج مطابق لـ $capacityLabel: ${glassTotal.toStringAsFixed(0)} $unit';
              } else if (isAbove) {
                message = lang == AppLanguage.french
                    ? '${openingPrefix}Attention : Épaisseur du vitrage ${glassTotal.toStringAsFixed(0)} $unit supérieure à $capacityLabel ${maximum.toStringAsFixed(0)} $unit'
                    : lang == AppLanguage.english
                    ? '${openingPrefix}Warning: Glass thickness ${glassTotal.toStringAsFixed(0)} $unit exceeds $capacityLabel ${maximum.toStringAsFixed(0)} $unit'
                    : '${openingPrefix}تنبيه: سُمك الزجاج ${glassTotal.toStringAsFixed(0)} $unit أكبر من $capacityLabel ${maximum.toStringAsFixed(0)} $unit';
              } else {
                message = lang == AppLanguage.french
                    ? '${openingPrefix}Attention : Épaisseur du vitrage ${glassTotal.toStringAsFixed(0)} $unit inférieure à $capacityLabel ${maximum.toStringAsFixed(0)} $unit'
                    : lang == AppLanguage.english
                    ? '${openingPrefix}Warning: Glass thickness ${glassTotal.toStringAsFixed(0)} $unit is less than $capacityLabel ${maximum.toStringAsFixed(0)} $unit'
                    : '${openingPrefix}تنبيه: سُمك الزجاج ${glassTotal.toStringAsFixed(0)} $unit أصغر من $capacityLabel ${maximum.toStringAsFixed(0)} $unit';
              }
            } else {
              final glassStr = glassTotal.toStringAsFixed(0);
              final jointStr = jointVitrage.toStringAsFixed(0);
              final packStr = totalPack.toStringAsFixed(0);
              final maxStr = maximum.toStringAsFixed(0);
              final gapStr = remainingGap.abs().toStringAsFixed(0);

              if (isAbove) {
                message = lang == AppLanguage.french
                    ? '${openingPrefix}Attention : Épaisseur ($glassStr $unit) + joints ($jointStr $unit) = $packStr $unit dépasse $capacityLabel ($maxStr $unit) de $gapStr $unit.'
                    : lang == AppLanguage.english
                    ? '${openingPrefix}Warning: Thickness ($glassStr $unit) + gaskets ($jointStr $unit) = $packStr $unit exceeds $capacityLabel ($maxStr $unit) by $gapStr $unit.'
                    : '${openingPrefix}تنبيه: السُمك ($glassStr $unit) + الجوانات ($jointStr $unit) = $packStr $unit يتجاوز $capacityLabel ($maxStr $unit) بـ $gapStr $unit.';
              } else if (remainingGap < 2.0) {
                if (spec.fittedJoints.isNotEmpty && isExact) {
                  message = lang == AppLanguage.french
                      ? '${openingPrefix}Épaisseur ($glassStr $unit) + joints sélectionnés ($jointStr $unit) = $packStr $unit, conforme à $capacityLabel ($maxStr $unit).'
                      : lang == AppLanguage.english
                      ? '${openingPrefix}Thickness ($glassStr $unit) + selected gaskets ($jointStr $unit) = $packStr $unit, matches $capacityLabel ($maxStr $unit).'
                      : '${openingPrefix}السُمك ($glassStr $unit) + الجوانات المختارة ($jointStr $unit) = $packStr $unit، مطابق لـ $capacityLabel ($maxStr $unit).';
                } else {
                  message = lang == AppLanguage.french
                      ? '${openingPrefix}Épaisseur ($glassStr $unit) + joints ($jointStr $unit) = $packStr $unit ($capacityLabelPlain : $maxStr $unit). Espace restant très réduit ($gapStr $unit).'
                      : lang == AppLanguage.english
                      ? '${openingPrefix}Thickness ($glassStr $unit) + gaskets ($jointStr $unit) = $packStr $unit ($capacityLabelPlain: $maxStr $unit). Remaining gap is very tight ($gapStr $unit).'
                      : '${openingPrefix}السُمك ($glassStr $unit) + الجوانات ($jointStr $unit) = $packStr $unit ($capacityLabelPlain: $maxStr $unit). الفراغ المتبقي ضيق جداً ($gapStr $unit).';
                }
              } else {
                message = lang == AppLanguage.french
                    ? '${openingPrefix}Épaisseur vitrage ($glassStr $unit) + joint vitrage ($jointStr $unit) = $packStr $unit | $capacityLabelPlain : $maxStr $unit. Le joint de bourrage recommandé doit être de $gapStr $unit.'
                    : lang == AppLanguage.english
                    ? '${openingPrefix}Glass thickness ($glassStr $unit) + glass gasket ($jointStr $unit) = $packStr $unit | $capacityLabelPlain: $maxStr $unit. Recommended wedge gasket (Joint Bourrage) should be $gapStr $unit.'
                    : '${openingPrefix}سُمك الزجاج ($glassStr $unit) + جوان الزجاج ($jointStr $unit) = $packStr $unit | $capacityLabelPlain: $maxStr $unit. إذاً الجوان المختار (Joint Bourrage) يجب أن يكون سُمكه $gapStr $unit.';
              }
            }

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          Widget? buildSlidingParcloseThicknessInfo() {
            final hasOpeningSystem = widget.model.zones.any(
              (candidate) =>
                  candidate.content == ZoneContent.singleSash ||
                  candidate.content == ZoneContent.doubleSash,
            );
            final hasSlidingSystem = widget.model.zones.any(
              (candidate) => candidate.content == ZoneContent.slidingSash,
            );
            if (!hasOpeningSystem ||
                !hasSlidingSystem ||
                spec.structure == GlassStructure.closed) {
              return null;
            }

            final usesParclose = widget.model.hasGlazingBeadForContext(
              sliding: true,
            );
            final maximum = widget.model.glazingCapacityForStructure(
              spec.structure,
              sliding: true,
            );
            if (maximum == null) return null;

            final glassTotal = spec.totalThickness(widget.model.allGlassCache);
            final sides = spec.jointTwoSides ? 2 : 1;
            final requiredPerSide = (maximum - glassTotal) / sides;
            final isAbove = requiredPerSide < 0;
            final color = isAbove ? Colors.red.shade700 : Colors.blue.shade700;
            final icon = isAbove
                ? Icons.warning_amber_rounded
                : Icons.info_outline_rounded;
            final glassStr = glassTotal.toStringAsFixed(0);
            final maxStr = maximum.toStringAsFixed(0);
            final jointStr = requiredPerSide.abs().toStringAsFixed(1);
            final sideText = sides == 2
                ? (lang == AppLanguage.french
                    ? 'des deux côtés'
                    : lang == AppLanguage.english
                    ? 'on both sides'
                    : 'من جهتين')
                : (lang == AppLanguage.french
                    ? 'd\'un seul côté'
                    : lang == AppLanguage.english
                    ? 'on one side'
                    : 'من جهة واحدة');
            final seriesName = widget.model.activeSlidingSeries?.name ?? '';
            final capacityLabel = usesParclose
                ? (lang == AppLanguage.french
                    ? 'la capacité parclose'
                    : lang == AppLanguage.english
                    ? 'glazing bead capacity'
                    : 'سعة البيركلوز')
                : (lang == AppLanguage.french
                    ? 'la capacité ouvrant'
                    : lang == AppLanguage.english
                    ? 'sash capacity'
                    : 'سعة الضلفة');
            final slidingPrefix = lang == AppLanguage.french
                ? 'Système coulissant ($seriesName) : '
                : lang == AppLanguage.english
                ? 'Sliding system ($seriesName): '
                : 'نظام المنزلق ($seriesName): ';
            final unit = lang == AppLanguage.arabic ? 'مم' : 'mm';
            final message = isAbove
                ? (lang == AppLanguage.french
                    ? '${slidingPrefix}Épaisseur vitrage $glassStr $unit dépasse $capacityLabel $maxStr $unit de $jointStr $unit.'
                    : lang == AppLanguage.english
                    ? '${slidingPrefix}Glass thickness $glassStr $unit exceeds $capacityLabel $maxStr $unit by $jointStr $unit.'
                    : '${slidingPrefix}سُمك الزجاج $glassStr مم يتجاوز $capacityLabel $maxStr مم بـ $jointStr مم.')
                : (lang == AppLanguage.french
                    ? '${slidingPrefix}Épaisseur vitrage $glassStr $unit, joint requis $jointStr $unit $sideText, et $capacityLabel $maxStr $unit.'
                    : lang == AppLanguage.english
                    ? '${slidingPrefix}Glass thickness $glassStr $unit, required gasket $jointStr $unit $sideText, and $capacityLabel $maxStr $unit.'
                    : '${slidingPrefix}سُمك الزجاج $glassStr مم، الجوان المطلوب $jointStr مم $sideText، و$capacityLabel $maxStr مم.');

            return Container(
              margin: const EdgeInsets.only(top: 8),
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: color.withValues(alpha: 0.35)),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Icon(icon, color: color, size: 18),
                  ),
                  const SizedBox(width: 7),
                  Expanded(
                    child: Text(
                      message,
                      style: TextStyle(
                        color: color,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        height: 1.35,
                      ),
                    ),
                  ),
                ],
              ),
            );
          }

          final parcloseThicknessInfo = buildParcloseThicknessInfo();
          final slidingParcloseThicknessInfo =
              buildSlidingParcloseThicknessInfo();
          final showSlidingJointSideSelector =
              !widget.model.isSlidingPVC &&
              (widget.systemMode == 'sliding' ||
                  widget.model.systemMode == 'sliding' ||
                  widget.model.zones.any(
                    (candidate) => candidate.content == ZoneContent.slidingSash,
                  ));
          final fallbackIntercallChoices = <Map<String, dynamic>>[
            {'thickness': 6, 'name': '6 مم'},
            {'thickness': 8, 'name': '8 مم'},
            {'thickness': 10, 'name': '10 مم'},
            {'thickness': 12, 'name': '12 مم'},
            {'thickness': 14, 'name': '14 مم'},
            {'thickness': 16, 'name': '16 مم'},
          ];
          final intercallChoices = List<Map<String, dynamic>>.from(
            widget.model.availableIntercalls.isNotEmpty
                ? widget.model.availableIntercalls
                : fallbackIntercallChoices,
          );
          final requiredIntercall = structure == GlassStructure.double
              ? widget.model.suggestedIntercallThicknessForDoubleGlass(
                  thicknessOuter:
                      spec.thicknessOuter ?? kDefaultGlassPaneThickness,
                  thicknessInner:
                      spec.thicknessInner ?? kDefaultGlassPaneThickness,
                  jointTwoSides: spec.jointTwoSides,
                )
              : null;

          Widget buildProcessingChip(
            String label,
            GlassProcessing type,
            bool isOuter,
            void Function(GlassProcessing) onTap,
          ) {
            final currentProc = isOuter
                ? spec.processingOuter
                : spec.processingInner;
            final effectiveProc = currentProc == GlassProcessing.tempered
                ? GlassProcessing.none
                : currentProc;
            final selected = effectiveProc == type;
            return FilterChip(
              label: Text(
                label,
                style: TextStyle(
                  fontSize: 11,
                  color: isDark
                      ? Colors.white
                      : (selected ? Colors.blue.shade900 : Colors.black87),
                ),
              ),
              selected: selected,
              backgroundColor: isDark ? const Color(0xFF2E2E3E) : null,
              selectedColor: isDark
                  ? Colors.blue.shade900.withValues(alpha: 0.5)
                  : Colors.blue.shade100,
              checkmarkColor: isDark ? Colors.white : Colors.blue.shade900,
              onSelected: (_) => onTap(type),
            );
          }

          Widget buildGlassLayer(bool isOuter) {
            final finish = isOuter ? spec.finishOuter : spec.finishInner;
            final color = isOuter ? spec.colorOuter : spec.colorInner;

            final isTempered = isOuter
                ? (spec.temperedOuter ||
                      spec.processingOuter == GlassProcessing.tempered)
                : (spec.temperedInner ||
                      spec.processingInner == GlassProcessing.tempered);

            void updateProcessing(GlassProcessing t) {
              final newSpec = spec.copyWith(
                processingOuter: isOuter ? t : null,
                processingInner: !isOuter ? t : null,
              );
              if (zone != null) {
                widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                );
              } else {
                _setViewState(() {
                  _tempGlassSpec = newSpec;
                });
              }
              _startPaintbrushMode(glassSpec: newSpec);
            }

            void updateTempered(bool val) {
              final legacyOuter =
                  isOuter && spec.processingOuter == GlassProcessing.tempered;
              final legacyInner =
                  !isOuter && spec.processingInner == GlassProcessing.tempered;

              final newSpec = spec.copyWith(
                processingOuter: legacyOuter ? GlassProcessing.none : null,
                processingInner: legacyInner ? GlassProcessing.none : null,
                temperedOuter: isOuter ? val : null,
                temperedInner: !isOuter ? val : null,
              );
              if (zone != null) {
                widget.model.updateSelectedZoneGlass(
                  processingOuter: legacyOuter ? GlassProcessing.none : null,
                  processingInner: legacyInner ? GlassProcessing.none : null,
                  temperedOuter: isOuter ? val : null,
                  temperedInner: !isOuter ? val : null,
                );
              } else {
                _setViewState(() {
                  _tempGlassSpec = newSpec;
                });
              }
              _startPaintbrushMode(glassSpec: newSpec);
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: 8, bottom: 4),
                  child: Text(
                    Localization.translate('نوع المعالجة:', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    buildProcessingChip(
                      Localization.translate('Simple', lang),
                      GlassProcessing.none,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      Localization.translate('Feuillette', lang),
                      GlassProcessing.laminated,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    buildProcessingChip(
                      Localization.translate('Low-e', lang),
                      GlassProcessing.lowE,
                      isOuter,
                      (t) => updateProcessing(t),
                    ),
                    FilterChip(
                      label: Text(
                        Localization.translate('Trempé', lang),
                        style: TextStyle(
                          fontSize: 11,
                          color: isDark
                              ? Colors.white
                              : (isTempered
                                    ? Colors.blue.shade900
                                    : Colors.black87),
                        ),
                      ),
                      selected: isTempered,
                      backgroundColor: isDark ? const Color(0xFF2E2E3E) : null,
                      selectedColor: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.5)
                          : Colors.blue.shade100,
                      checkmarkColor: isDark
                          ? Colors.white
                          : Colors.blue.shade900,
                      onSelected: (val) {
                        updateTempered(val);
                      },
                    ),
                  ],
                ),
                Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 4),
                  child: Text(
                    Localization.translate('المظهر:', lang),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children:
                      [
                            GlassFinish.clair,
                            GlassFinish.stopSol,
                            GlassFinish.sable,
                            GlassFinish.delta,
                            GlassFinish.tuC,
                            GlassFinish.nevada,
                            GlassFinish.cuisine,
                            GlassFinish.aFleur,
                          ]
                          .map(
                            (f) => Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ContentButton(
                                label: _getFinishName(f),
                                icon: Icons.blur_on_rounded,
                                selected: finish == f,
                                showWarning:
                                    widget.model.getPriceForFinish(f, color) ==
                                    0.0,
                                onPressed: () {
                                  final GlassColor nextColor =
                                      f == GlassFinish.stopSol
                                      ? (isOuter
                                            ? spec.colorOuter
                                            : spec.colorInner)
                                      : GlassColor.transparent;
                                  double defThick = widget.model
                                      .getThicknessForFinish(f, nextColor);
                                  if (defThick == 0.0) defThick = 5.0;

                                  final newSpec = fitDoubleGlassToParclose(
                                    spec.copyWith(
                                      finishOuter: isOuter ? f : null,
                                      finishInner: !isOuter ? f : null,
                                      colorOuter: isOuter ? nextColor : null,
                                      colorInner: !isOuter ? nextColor : null,
                                      thicknessOuter: isOuter ? defThick : null,
                                      thicknessInner: !isOuter
                                          ? defThick
                                          : null,
                                    ),
                                  );
                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlass(
                                      finishOuter: isOuter ? f : null,
                                      finishInner: !isOuter ? f : null,
                                      colorOuter: isOuter ? nextColor : null,
                                      colorInner: !isOuter ? nextColor : null,
                                      thicknessOuter: isOuter ? defThick : null,
                                      thicknessInner: !isOuter
                                          ? defThick
                                          : null,
                                      intercallThickness:
                                          newSpec.structure ==
                                              GlassStructure.double
                                          ? newSpec.intercallThickness
                                          : null,
                                    );
                                  } else {
                                    _setViewState(() {
                                      _tempGlassSpec = newSpec;
                                    });
                                  }
                                  _startPaintbrushMode(glassSpec: newSpec);
                                  if (f == GlassFinish.stopSol) {
                                    _autoScrollDrawer();
                                  }
                                },
                              ),
                            ),
                          )
                          .toList(),
                ),
                if (finish == GlassFinish.stopSol) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 4),
                    child: Text(
                      _tr('لون الزجاج (ستوبسول):'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      return Wrap(
                        spacing: 6,
                        runSpacing: 6,
                        children: GlassColor.values
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 6),
                                child: _ContentButton(
                                  label: _getColorName(c),
                                  icon: Icons.palette_rounded,
                                  selected: color == c,
                                  showWarning:
                                      widget.model.getPriceForFinish(
                                        finish,
                                        c,
                                      ) ==
                                      0.0,
                                  onPressed: () {
                                    final double defThick = widget.model
                                        .getThicknessForFinish(
                                          isOuter
                                              ? spec.finishOuter
                                              : spec.finishInner,
                                          c,
                                        );
                                    double resolvedThick = defThick == 0.0
                                        ? 5.0
                                        : defThick;

                                    final newSpec = fitDoubleGlassToParclose(
                                      spec.copyWith(
                                        colorOuter: isOuter ? c : null,
                                        colorInner: !isOuter ? c : null,
                                        thicknessOuter: isOuter
                                            ? resolvedThick
                                            : null,
                                        thicknessInner: !isOuter
                                            ? resolvedThick
                                            : null,
                                      ),
                                    );
                                    if (zone != null) {
                                      widget.model.updateSelectedZoneGlass(
                                        colorOuter: isOuter ? c : null,
                                        colorInner: !isOuter ? c : null,
                                        thicknessOuter: isOuter
                                            ? resolvedThick
                                            : null,
                                        thicknessInner: !isOuter
                                            ? resolvedThick
                                            : null,
                                        intercallThickness:
                                            newSpec.structure ==
                                                GlassStructure.double
                                            ? newSpec.intercallThickness
                                            : null,
                                      );
                                    } else {
                                      _setViewState(() {
                                        _tempGlassSpec = newSpec;
                                      });
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                    _autoScrollDrawer();
                                  },
                                ),
                              ),
                            )
                            .toList(),
                      );
                    },
                  ),
                ],
                const SizedBox(height: 12),
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Text(
                    Localization.translate('سمك الزجاج:', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 11,
                    ),
                  ),
                ),
                Builder(
                  builder: (context) {
                    var thicknesses = widget.model.getAvailableThicknesses(
                      finish,
                      color,
                    );
                    final isSliding67Family = widget.model.isSliding67Family;
                    final isSliding =
                        widget.systemMode == 'sliding' ||
                        widget.model.systemMode == 'sliding' ||
                        zone?.content == ZoneContent.slidingSash;
                    if (isSliding && isSliding67Family) {
                      final double minGasket = spec.jointTwoSides ? 4.0 : 2.0;
                      final double maxAllowed =
                          24.0 - minGasket; // 20.0 or 22.0
                      if (spec.structure == GlassStructure.double) {
                        final double tOther = isOuter
                            ? (spec.thicknessInner ??
                                  kDefaultGlassPaneThickness)
                            : (spec.thicknessOuter ??
                                  kDefaultGlassPaneThickness);
                        final int intercall = spec.intercallThickness;
                        thicknesses = thicknesses
                            .where(
                              (thick) =>
                                  (thick + intercall + tOther) <= maxAllowed,
                            )
                            .toList();
                      } else {
                        thicknesses = thicknesses
                            .where((thick) => thick <= maxAllowed)
                            .toList();
                      }
                    }
                    final double currentThickness = isOuter
                        ? (spec.thicknessOuter ??
                              widget.model.getThicknessForFinish(finish, color))
                        : (spec.thicknessInner ??
                              widget.model.getThicknessForFinish(
                                finish,
                                color,
                              ));

                    return _HorizontalWheelScrollArea(
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: thicknesses.map((thickVal) {
                            final isSelected = currentThickness == thickVal;
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ContentButton(
                                label: '${thickVal.toStringAsFixed(0)} مم',
                                icon: Icons.line_weight_rounded,
                                selected: isSelected,
                                onPressed: () {
                                  final newSpec = fitDoubleGlassToParclose(
                                    spec.copyWith(
                                      thicknessOuter: isOuter ? thickVal : null,
                                      thicknessInner: !isOuter
                                          ? thickVal
                                          : null,
                                    ),
                                  );
                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlass(
                                      thicknessOuter: isOuter ? thickVal : null,
                                      thicknessInner: !isOuter
                                          ? thickVal
                                          : null,
                                      intercallThickness:
                                          newSpec.structure ==
                                              GlassStructure.double
                                          ? newSpec.intercallThickness
                                          : null,
                                    );
                                  } else {
                                    _setViewState(() {
                                      _tempGlassSpec = newSpec;
                                    });
                                  }
                                  _startPaintbrushMode(glassSpec: newSpec);
                                  _autoScrollDrawer();
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
              ],
            );
          }

          return ListView(
            controller: _leftDrawerScrollController,
            padding: const EdgeInsets.all(12.0),
            children: [
              Row(
                children: [
                  Icon(
                    Icons.settings_outlined,
                    color: Colors.blue.shade800,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    Localization.translate('خصائص الزجاج', lang),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade800,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
              const Divider(),
              if (parcloseThicknessInfo != null) parcloseThicknessInfo,
              if (slidingParcloseThicknessInfo != null)
                slidingParcloseThicknessInfo,
              if (showSlidingJointSideSelector) ...[
                const SizedBox(height: 10),
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    _tr('جهة جوان البوراج للزجاج'),
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.blue.shade200
                          : Colors.blue.shade800,
                    ),
                  ),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: Text(_tr('جهة واحدة')),
                      selected: !spec.jointTwoSides,
                      onSelected: (_) {
                        widget.model.updateAllSlidingJointSides(false);
                        _setViewState(() {
                          _tempGlassSpec = spec.copyWith(jointTwoSides: false);
                        });
                      },
                    ),
                    ChoiceChip(
                      label: Text(_tr('جهتين')),
                      selected: spec.jointTwoSides,
                      onSelected: (_) {
                        widget.model.updateAllSlidingJointSides(true);
                        _setViewState(() {
                          _tempGlassSpec = spec.copyWith(jointTwoSides: true);
                        });
                      },
                    ),
                  ],
                ),
              ],
              if (targetZone != null &&
                  targetZone.content == ZoneContent.doubleSash) ...[
                Row(
                  children: [
                    Icon(
                      Icons.splitscreen_outlined,
                      color: isDark
                          ? Colors.blue.shade300
                          : Colors.blue.shade800,
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _tr('نسبة تقسيم الضلفة (ضلفة أكبر من ضلفة)'),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.blue.shade300
                              : Colors.blue.shade800,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Card(
                  color: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.blue.shade50.withValues(alpha: 0.5),
                  elevation: 0,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: isDark
                          ? Colors.blue.shade400
                          : Colors.blue.shade100,
                      width: isDark ? 1.5 : 1.0,
                    ),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12.0),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              '${Localization.translate('اليسرى', lang)}: ${(_visualDoubleSashRatio(targetZone) * 100).round()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                            Text(
                              '${Localization.translate('اليمنى', lang)}: ${((1.0 - _visualDoubleSashRatio(targetZone)) * 100).round()}%',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 11,
                                color: isDark ? Colors.white70 : Colors.black87,
                              ),
                            ),
                          ],
                        ),
                        Slider(
                          // The slider follows the leaves as drawn: moving it
                          // right always widens the leaf shown on the left.
                          value: _visualDoubleSashRatio(
                            targetZone,
                          ).clamp(0.15, 0.85).toDouble(),
                          min: 0.15,
                          max: 0.85,
                          divisions: 70,
                          label:
                              '${(_visualDoubleSashRatio(targetZone) * 100).round()}%',
                          // One undo step per drag instead of one per tick.
                          onChangeStart: (_) =>
                              widget.model.saveSnapshotOutside(),
                          onChanged: (val) {
                            widget.model.updateZoneDoubleSashRatio(
                              targetZone!.id,
                              _storedDoubleSashRatio(val),
                              saveHistory: false,
                            );
                          },
                        ),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            OutlinedButton(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 4,
                                ),
                                minimumSize: Size.zero,
                                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                                side: BorderSide(
                                  color: isDark
                                      ? Colors.blue.shade400
                                      : Colors.blue.shade100,
                                ),
                                foregroundColor: isDark
                                    ? Colors.blue.shade200
                                    : Colors.blue.shade800,
                              ),
                              onPressed: () {
                                widget.model.updateZoneDoubleSashRatio(
                                  targetZone!.id,
                                  0.5,
                                );
                              },
                              child: Text(
                                _tr('متساويين (50%)'),
                                style: TextStyle(fontSize: 10),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Builder(
                          builder: (context) {
                            // Same cutting size as the label drawn on the
                            // left leaf (overlap added, PVC weld loss removed).
                            final currentLeftWidth =
                                _shownDoubleSashCuttingWidth(
                                  targetZone!,
                                  _visualDoubleSashRatio(targetZone),
                                ).round();
                            if (!_leftSashFocusNode.hasFocus) {
                              _leftSashWidthController.text = currentLeftWidth
                                  .toString();
                            }

                            void applySashWidth() {
                              final valStr = _leftSashWidthController.text
                                  .trim();
                              final val = double.tryParse(valStr);
                              if (val == null) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      _tr('يرجى إدخال قياس صحيح بالمليمتر'),
                                    ),
                                    backgroundColor: Colors.red,
                                  ),
                                );
                                return;
                              }

                              // 15–85 % of the leaves' total cutting width,
                              // the same range as the slider and the drag.
                              final minVal = _shownDoubleSashCuttingWidth(
                                targetZone!,
                                0.15,
                                );
                              final maxVal = _shownDoubleSashCuttingWidth(
                                targetZone,
                                0.85,
                                );
                              if (!_acceptDimension(val, minVal, maxVal)) {
                                return;
                              }

                              final visualRatio = _visualRatioForLeftLeafCut(
                                targetZone,
                                val,
                              ).clamp(0.15, 0.85).toDouble();
                              widget.model.updateZoneDoubleSashRatio(
                                targetZone.id,
                                _storedDoubleSashRatio(visualRatio),
                              );
                              _leftSashFocusNode.unfocus();
                            }

                            return Row(
                              children: [
                                Expanded(
                                  child: SizedBox(
                                    height: 32,
                                    child: TextField(
                                      controller: _leftSashWidthController,
                                      focusNode: _leftSashFocusNode,
                                      keyboardType: TextInputType.number,
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'عرض الضلفة اليسرى (مم)',
                                          lang,
                                        ),
                                        labelStyle: TextStyle(
                                          fontSize: 10,
                                          color: isDark ? Colors.white70 : null,
                                        ),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              horizontal: 8,
                                              vertical: 4,
                                            ),
                                        enabledBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? Colors.white30
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        focusedBorder: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                          borderSide: BorderSide(
                                            color: isDark
                                                ? Colors.blue.shade400
                                                : Colors.blue,
                                          ),
                                        ),
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            6,
                                          ),
                                        ),
                                        isDense: true,
                                      ),
                                      style: TextStyle(
                                        fontSize: 12,
                                        color: isDark
                                            ? Colors.white
                                            : Colors.black,
                                      ),
                                      onSubmitted: (_) => applySashWidth(),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                    ),
                                    minimumSize: const Size(0, 32),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    backgroundColor: Colors.blue.shade700,
                                    foregroundColor: Colors.white,
                                  ),
                                  onPressed: applySashWidth,
                                  child: Text(
                                    Localization.translate('تطبيق', lang),
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const Divider(),
              ],

              Padding(
                padding: EdgeInsets.only(top: 8, bottom: 8),
                child: Text(
                  Localization.translate('هيكل الزجاج:', lang),
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              _HorizontalWheelScrollArea(
                builder: (context, controller) => SingleChildScrollView(
                  controller: controller,
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: GlassStructure.values
                        .map(
                          (s) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: _ContentButton(
                              label: _getStructureName(s),
                              icon: Icons.layers_rounded,
                              selected: structure == s,
                              onPressed: () async {
                                String? defaultSubtype;
                                String? defaultColor;
                                if (s == GlassStructure.closed) {
                                  final panneaux = widget.model.allGlassCache
                                      .where(
                                        (g) =>
                                            g['type']
                                                .toString()
                                                .toLowerCase() ==
                                            'panneau',
                                      )
                                      .toList();
                                  final subtypes = panneaux
                                      .map(
                                        (g) => (g['subtype'] ?? '').toString(),
                                      )
                                      .where((s) => s.isNotEmpty)
                                      .toSet()
                                      .toList();
                                  if (subtypes.isNotEmpty) {
                                    final savedSubtype = spec.panneauSubtype;
                                    defaultSubtype =
                                        spec.structure ==
                                                GlassStructure.closed &&
                                            savedSubtype != null &&
                                            subtypes.any(
                                              (value) =>
                                                  value.toLowerCase() ==
                                                  savedSubtype.toLowerCase(),
                                            )
                                        ? savedSubtype
                                        : subtypes.firstWhere(
                                            (value) =>
                                                !isDecorPanelSubtype(value),
                                            orElse: () => subtypes.first,
                                          );
                                    final subRows = panneaux
                                        .where(
                                          (g) =>
                                              (g['subtype'] ?? '')
                                                  .toString()
                                                  .toLowerCase() ==
                                              defaultSubtype!.toLowerCase(),
                                        )
                                        .toList();
                                    if (subRows.isNotEmpty) {
                                      final colorsList = subRows
                                          .map(
                                            (g) => (g['color'] ?? '')
                                                .toString()
                                                .trim(),
                                          )
                                          .where((c) => c.isNotEmpty)
                                          .toSet()
                                          .toList();
                                      if (colorsList.isNotEmpty) {
                                        defaultColor =
                                            spec.panneauColor ??
                                            colorsList.first;
                                      }
                                    }
                                  }
                                }

                                double? defaultThickOuter;
                                double? defaultThickInner;
                                final GlassColor? structureColorOuter =
                                    s != GlassStructure.closed &&
                                        spec.finishOuter != GlassFinish.stopSol
                                    ? GlassColor.transparent
                                    : null;
                                final GlassColor? structureColorInner =
                                    s != GlassStructure.closed &&
                                        spec.finishInner != GlassFinish.stopSol
                                    ? GlassColor.transparent
                                    : null;
                                if (s == GlassStructure.double) {
                                  defaultThickOuter =
                                      spec.thicknessOuter ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishOuter,
                                        structureColorOuter ?? spec.colorOuter,
                                      );
                                  defaultThickInner =
                                      spec.thicknessInner ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishInner,
                                        structureColorInner ?? spec.colorInner,
                                      );
                                  if (defaultThickOuter == 0.0) {
                                    defaultThickOuter = 5.0;
                                  }
                                  if (defaultThickInner == 0.0) {
                                    defaultThickInner = 5.0;
                                  }
                                } else if (s == GlassStructure.simple) {
                                  defaultThickOuter =
                                      spec.thicknessOuter ??
                                      widget.model.getThicknessForFinish(
                                        spec.finishOuter,
                                        structureColorOuter ?? spec.colorOuter,
                                      );
                                  if (defaultThickOuter == 0.0) {
                                    defaultThickOuter = 5.0;
                                  }
                                }

                                final newSpec = fitDoubleGlassToParclose(
                                  spec.copyWith(
                                    structure: s,
                                    hasGas:
                                        s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                        ? true
                                        : null,
                                    panneauSubtype: defaultSubtype,
                                    panneauColor: defaultColor,
                                    colorOuter: structureColorOuter,
                                    colorInner: structureColorInner,
                                    thicknessOuter: defaultThickOuter,
                                    thicknessInner: defaultThickInner,
                                  ),
                                );
                                if (zone != null) {
                                  await widget.model.updateSelectedZoneGlass(
                                    structure: s,
                                    hasGas:
                                        s == GlassStructure.double &&
                                            spec.structure !=
                                                GlassStructure.double
                                        ? true
                                        : null,
                                    panneauSubtype: defaultSubtype,
                                    panneauColor: defaultColor,
                                    colorOuter: structureColorOuter,
                                    colorInner: structureColorInner,
                                    thicknessOuter: defaultThickOuter,
                                    thicknessInner: defaultThickInner,
                                    intercallThickness:
                                        newSpec.structure ==
                                            GlassStructure.double
                                        ? newSpec.intercallThickness
                                        : null,
                                  );
                                } else {
                                  _setViewState(() {
                                    _tempGlassSpec = newSpec;
                                  });
                                }
                                _startPaintbrushMode(glassSpec: newSpec);
                                if (s == GlassStructure.double) {
                                  _autoScrollDrawer();
                                }
                              },
                            ),
                          ),
                        )
                        .toList(),
                  ),
                ),
              ),
              const SizedBox(height: 8),
              if (structure == GlassStructure.closed) ...[
                Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    Localization.translate('المظهر (بانو):', lang),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 11),
                  ),
                ),
                Builder(
                  builder: (context) {
                    final panneaux = widget.model.allGlassCache
                        .where(
                          (g) =>
                              g['type'].toString().toLowerCase() == 'panneau',
                        )
                        .toList();
                    final subtypes = panneaux
                        .map((g) => (g['subtype'] ?? '').toString())
                        .where((s) => s.isNotEmpty)
                        .toSet()
                        .toList();

                    // دائماً نضيف البارداج كخيار ثابت من بروفيلات السلسلة.
                    // تسعيره لاحقاً يكون بعدد قطع المخزون الكاملة.
                    const String bardageKey = 'bardage';
                    if (!subtypes.any(isBardagePanelSubtype)) {
                      subtypes.add(bardageKey);
                    }

                    String getArabicSubtypeName(String sub) {
                      final s = sub.toLowerCase();
                      if (s.contains('resine') ||
                          s.contains('ارزين') ||
                          s.contains('أرزين')) {
                        return 'ارزين';
                      }
                      if (s.contains('plexi')) return 'بليكسي';
                      if (s.contains('decore') || s.contains('ديكور')) {
                        return 'بانو ديكور';
                      }
                      if (s.contains('sandwitch') ||
                          s.contains('sandwich') ||
                          s == 'panneau' ||
                          s == 'بانو') {
                        return 'بانو';
                      }
                      if (s.contains('aluco') || s.contains('الوكو')) {
                        return 'الوكو';
                      }
                      if (isBardagePanelSubtype(s)) {
                        return 'بارداش';
                      }
                      return sub;
                    }

                    IconData getSubtypeIcon(String sub) {
                      final s = sub.toLowerCase();
                      if (isBardagePanelSubtype(s)) {
                        return Icons.view_stream_rounded;
                      }
                      return Icons.blur_on_rounded;
                    }

                    return _HorizontalWheelScrollArea(
                      builder: (context, controller) => SingleChildScrollView(
                        controller: controller,
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: subtypes.map((sub) {
                            final isSelected =
                                (spec.panneauSubtype ?? '').toLowerCase() ==
                                sub.toLowerCase();
                            final isBardage = isBardagePanelSubtype(sub);
                            final isDecor = isDecorPanelSubtype(sub);
                            return Padding(
                              padding: const EdgeInsets.only(right: 6),
                              child: _ContentButton(
                                label: getArabicSubtypeName(sub),
                                icon: getSubtypeIcon(sub),
                                selected: isSelected,
                                onPressed: () async {
                                  final subRows = panneaux
                                      .where(
                                        (g) =>
                                            (g['subtype'] ?? '')
                                                .toString()
                                                .toLowerCase() ==
                                            sub.toLowerCase(),
                                      )
                                      .toList();
                                  final selectedFrameColor =
                                      (widget.model.selectedDbColor?['name'] ??
                                              widget
                                                  .model
                                                  .selectedDbColor?['color_name'] ??
                                              widget.model.frameColor.name)
                                          .toString()
                                          .trim();
                                  String firstColor = isBardage
                                      ? selectedFrameColor
                                      : 'أبيض';
                                  if (!isBardage && subRows.isNotEmpty) {
                                    final colorsList = subRows
                                        .map(
                                          (g) => (g['color'] ?? '')
                                              .toString()
                                              .trim(),
                                        )
                                        .where((c) => c.isNotEmpty)
                                        .toSet()
                                        .toList();
                                    if (colorsList.isNotEmpty) {
                                      firstColor = colorsList.first;
                                    }
                                  }

                                  final sLower = sub.toLowerCase();
                                  final GlassFinish targetFinish;
                                  if (isBardage) {
                                    targetFinish = GlassFinish.bardage;
                                  } else if (sLower.contains('resine') ||
                                      sLower.contains('ارزين') ||
                                      sLower.contains('أرزين')) {
                                    targetFinish = GlassFinish.resine;
                                  } else if (sLower.contains('plexi') ||
                                      sLower.contains('بليكسي')) {
                                    targetFinish = GlassFinish.plexyGlass;
                                  } else if (sLower.contains('decor') ||
                                      sLower.contains('ديكور')) {
                                    targetFinish =
                                        GlassFinish.paneauSandwitchDecore;
                                  } else {
                                    targetFinish = GlassFinish.paneauSandwitch;
                                  }

                                  final bardageProfile = isBardage
                                      ? widget
                                            .model
                                            .componentOverrides['البارداج (Bardage)']
                                      : null;
                                  final rawBardageThickness =
                                      bardageProfile?['thickness'];
                                  final bardageThickness =
                                      rawBardageThickness is num
                                      ? rawBardageThickness.toDouble()
                                      : double.tryParse(
                                          rawBardageThickness?.toString() ?? '',
                                        );
                                  final rawBardageId = bardageProfile?['id'];
                                  final bardageProfileId = rawBardageId is num
                                      ? rawBardageId.toInt()
                                      : int.tryParse(
                                          rawBardageId?.toString() ?? '',
                                        );
                                  Map<String, dynamic>? decorProduct;
                                  if (isDecor && subRows.isNotEmpty) {
                                    decorProduct = subRows.firstWhere(
                                      (row) =>
                                          row['id']?.toString() ==
                                          spec.panneauProductId?.toString(),
                                      orElse: () => subRows.first,
                                    );
                                    final productColor =
                                        (decorProduct['color'] ?? '')
                                            .toString()
                                            .trim();
                                    if (productColor.isNotEmpty) {
                                      firstColor = productColor;
                                    }
                                  }
                                  final rawDecorId = decorProduct?['id'];
                                  final decorProductId = rawDecorId is num
                                      ? rawDecorId.toInt()
                                      : int.tryParse(
                                          rawDecorId?.toString() ?? '',
                                        );
                                  final decorThickness = decorProduct == null
                                      ? null
                                      : _catalogNumber(
                                          decorProduct,
                                          'thickness',
                                        );
                                  final newSpec = spec.copyWith(
                                    panneauSubtype: sub,
                                    panneauColor: firstColor,
                                    bardageUsesFrameColor: isBardage
                                        ? true
                                        : spec.bardageUsesFrameColor,
                                    structure: GlassStructure.closed,
                                    finishOuter: targetFinish,
                                    finishInner: targetFinish,
                                    panneauProductId: isBardage
                                        ? bardageProfileId
                                        : decorProductId,
                                    decorDesignCode:
                                        (isDecor && decorProduct != null)
                                        ? decorProduct['decor_design_code']
                                              ?.toString()
                                        : null,
                                    thicknessOuter: isBardage
                                        ? bardageThickness
                                        : decorThickness,
                                  );
                                  if (zone != null) {
                                    if (isDecor) {
                                      final placement =
                                          await _prepareDecorPanelPlacement(
                                            zone: zone,
                                            cellId: widget.model.activeSubZone,
                                            spec: newSpec,
                                          );
                                      if (!placement.allowed) return;
                                      widget.model.activeSubZone =
                                          placement.cellId;
                                    }
                                    await widget.model.updateSelectedZoneGlass(
                                      panneauSubtype: sub,
                                      panneauColor: firstColor,
                                      bardageUsesFrameColor: isBardage
                                          ? true
                                          : spec.bardageUsesFrameColor,
                                      finishOuter: targetFinish,
                                      finishInner: targetFinish,
                                      structure: GlassStructure.closed,
                                      panneauProductId: isBardage
                                          ? bardageProfileId
                                          : decorProductId,
                                      decorDesignCode:
                                          (isDecor && decorProduct != null)
                                          ? decorProduct['decor_design_code']
                                                ?.toString()
                                          : null,
                                      thicknessOuter: isBardage
                                          ? bardageThickness
                                          : decorThickness,
                                    );
                                  } else {
                                    _setViewState(() {
                                      _tempGlassSpec = newSpec;
                                    });
                                  }
                                  _startPaintbrushMode(glassSpec: newSpec);
                                  _autoScrollDrawer();
                                },
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                    );
                  },
                ),
                if (isDecorPanelSubtype(spec.panneauSubtype)) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      _tr('رسم ومقاس البانو ديكور:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final uniqueProducts = <String, Map<String, dynamic>>{};
                      for (final product in widget.model.allGlassCache) {
                        if (product['type'].toString().toLowerCase() !=
                                'panneau' ||
                            !isDecorPanelSubtype(
                              product['subtype']?.toString(),
                            )) {
                          continue;
                        }
                        final id = product['id']?.toString();
                        if (id != null && id.isNotEmpty) {
                          uniqueProducts.putIfAbsent(id, () => product);
                        }
                      }
                      final products = uniqueProducts.values.toList();
                      if (products.isEmpty) {
                        return Text(
                          _tr('لا يوجد بانو ديكور في منتجات الزجاج.'),
                          style: TextStyle(color: Colors.red, fontSize: 10),
                        );
                      }
                      final savedId = spec.panneauProductId?.toString();
                      final currentId = uniqueProducts.containsKey(savedId)
                          ? savedId
                          : products.first['id'].toString();

                      final currentProduct = uniqueProducts[currentId]!;
                      final currentDesignCode =
                          currentProduct['decor_design_code']?.toString();

                      return Column(
                        children: [
                          DropdownButtonFormField<String>(
                            value: currentId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              isDense: true,
                              border: OutlineInputBorder(),
                            ),
                            selectedItemBuilder: (context) =>
                                products.map((product) {
                                  final name = (product['name'] ?? 'بانو ديكور')
                                      .toString();
                                  return Row(
                                    children: [
                                      DecorPanelDesignPreview(
                                        designCode: product['decor_design_code']
                                            ?.toString(),
                                        width: 24,
                                        height: 38,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          name,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(fontSize: 10),
                                        ),
                                      ),
                                    ],
                                  );
                                }).toList(),
                            items: products.map((product) {
                              final width = _catalogNumber(
                                product,
                                'visible_width',
                              );
                              final height = _catalogNumber(product, 'height');
                              final name = (product['name'] ?? 'بانو ديكور')
                                  .toString();
                              return DropdownMenuItem<String>(
                                value: product['id'].toString(),
                                child: Row(
                                  children: [
                                    DecorPanelDesignPreview(
                                      designCode: product['decor_design_code']
                                          ?.toString(),
                                      width: 30,
                                      height: 48,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        '$name - ${width.toStringAsFixed(0)} × ${height.toStringAsFixed(0)} مم',
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontSize: 10),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                            }).toList(),
                            onChanged: (value) async {
                              if (value == null) return;
                              final chosen = uniqueProducts[value]!;
                              final chosenId = int.tryParse(value);
                              final thickness = _catalogNumber(
                                chosen,
                                'thickness',
                              );
                              final colorsForProduct = widget
                                  .model
                                  .allGlassCache
                                  .where(
                                    (row) =>
                                        row['id']?.toString() == value &&
                                        (row['color'] ?? '')
                                            .toString()
                                            .trim()
                                            .isNotEmpty,
                                  )
                                  .map(
                                    (row) =>
                                        (row['color'] ?? '').toString().trim(),
                                  )
                                  .toList();
                              final selectedColor =
                                  colorsForProduct.any(
                                    (color) =>
                                        color.toLowerCase() ==
                                        (spec.panneauColor ?? '').toLowerCase(),
                                  )
                                  ? spec.panneauColor
                                  : (colorsForProduct.isEmpty
                                        ? spec.panneauColor
                                        : colorsForProduct.first);
                              final newSpec = spec.copyWith(
                                panneauProductId: chosenId,
                                decorDesignCode: chosen['decor_design_code']
                                    ?.toString(),
                                panneauColor: selectedColor,
                                thicknessOuter: thickness,
                              );
                              if (zone != null) {
                                final placement =
                                    await _prepareDecorPanelPlacement(
                                      zone: zone,
                                      cellId: widget.model.activeSubZone,
                                      spec: newSpec,
                                    );
                                if (!placement.allowed) return;
                                widget.model.activeSubZone = placement.cellId;
                                await widget.model.updateSelectedZoneGlass(
                                  panneauProductId: chosenId,
                                  decorDesignCode: chosen['decor_design_code']
                                      ?.toString(),
                                  panneauColor: selectedColor,
                                  thicknessOuter: thickness,
                                );
                              } else {
                                _setViewState(() => _tempGlassSpec = newSpec);
                              }
                              _startPaintbrushMode(glassSpec: newSpec);
                            },
                          ),
                          if (DecorPanelDesignCatalog.isSupported(
                            currentDesignCode,
                          )) ...[
                            const SizedBox(height: 10),
                            DecorPanelDesignPreview(
                              designCode: currentDesignCode,
                              panelColor: getEffectiveGradientColors(
                                FrameColor.white,
                                {'name': spec.panneauColor ?? 'أبيض'},
                              )[1],
                              width: 84,
                              height: 140,
                            ),
                          ],
                        ],
                      );
                    },
                  ),
                ],
                // ألوان البانو — تُخفى عند اختيار البارداج لأنه بروفيل بلا ألوان
                if (!(spec.panneauSubtype ?? '').toLowerCase().contains(
                  'bardage',
                )) ...[
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 8),
                    child: Text(
                      _tr('لون البانو:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final panneaux = widget.model.allGlassCache
                          .where(
                            (g) =>
                                g['type'].toString().toLowerCase() == 'panneau',
                          )
                          .toList();
                      final activeSub = spec.panneauSubtype ?? '';
                      final activeIsDecor = isDecorPanelSubtype(activeSub);
                      final subRows = panneaux
                          .where(
                            (g) =>
                                (g['subtype'] ?? '').toString().toLowerCase() ==
                                    activeSub.toLowerCase() &&
                                (!activeIsDecor ||
                                    spec.panneauProductId == null ||
                                    g['id']?.toString() ==
                                        spec.panneauProductId.toString()),
                          )
                          .toList();
                      List<String> allowedColors = [];
                      if (subRows.isNotEmpty) {
                        allowedColors = subRows
                            .map((g) => (g['color'] ?? '').toString().trim())
                            .where((c) => c.isNotEmpty)
                            .toSet()
                            .toList();
                      }
                      if (allowedColors.isEmpty) {
                        allowedColors = ['أبيض', 'بني', 'بيج', 'رمادي', 'أسود'];
                      }

                      return _HorizontalWheelScrollArea(
                        builder: (context, controller) => SingleChildScrollView(
                          controller: controller,
                          scrollDirection: Axis.horizontal,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: allowedColors.map((colorName) {
                                final isSelected =
                                    (spec.panneauColor ?? '').toLowerCase() ==
                                    colorName.toLowerCase();
                                final fakeDbColor = {'name': colorName};
                                final woodImage = _getWoodTextureImage(
                                  fakeDbColor,
                                );
                                final parsedColor = getEffectiveGradientColors(
                                  FrameColor.white,
                                  fakeDbColor,
                                )[1];

                                return Padding(
                                  padding: const EdgeInsets.only(right: 12),
                                  child: GestureDetector(
                                    onTap: () {
                                      final newSpec = spec.copyWith(
                                        panneauColor: colorName,
                                      );
                                      if (zone != null) {
                                        widget.model.updateSelectedZoneGlass(
                                          panneauColor: colorName,
                                        );
                                      } else {
                                        _setViewState(() {
                                          _tempGlassSpec = newSpec;
                                        });
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    },
                                    child: Column(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Container(
                                          width: isSelected ? 34 : 28,
                                          height: isSelected ? 34 : 28,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: woodImage != null
                                                ? null
                                                : parsedColor,
                                            image: woodImage,
                                            border: Border.all(
                                              color: isSelected
                                                  ? Colors.blue
                                                  : Colors.grey.shade400,
                                              width: isSelected ? 2.5 : 1.0,
                                            ),
                                            boxShadow: [
                                              if (isSelected)
                                                BoxShadow(
                                                  color: Colors.blue.withValues(
                                                    alpha: 0.3,
                                                  ),
                                                  blurRadius: 4,
                                                  spreadRadius: 1,
                                                ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          colorName,
                                          style: TextStyle(
                                            fontSize: 10,
                                            fontWeight: isSelected
                                                ? FontWeight.bold
                                                : FontWeight.normal,
                                            color: isSelected
                                                ? Colors.blue.shade900
                                                : Colors.black87,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              }).toList(),
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ] else ...[
                  // اختيار مقاس البارداج المتوفر في قاعدة البيانات
                  Padding(
                    padding: EdgeInsets.only(top: 12, bottom: 6),
                    child: Text(
                      _tr('مقاس وسماكة البارداج:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      // 1. نبحث أولاً في بروفيلات السيستم/السلسلة الحالية عن قطاع بارداج
                      final bardageSections =
                          (activeSeriesForSystem?.sections ?? []).where((s) {
                            final t = s.type.toLowerCase().trim();
                            final n = s.name.toLowerCase().trim();
                            return isBardagePanelSubtype(t) ||
                                isBardagePanelSubtype(n);
                          }).toList();

                      final List<Map<String, dynamic>> productsList = [];

                      if (bardageSections.isNotEmpty) {
                        for (var s in bardageSections) {
                          productsList.add({...s.toMap(), 'is_profile': true});
                        }
                      }

                      final savedProductId = spec.panneauProductId;
                      final int? currentProductId =
                          productsList.any((p) => p['id'] == savedProductId)
                          ? savedProductId
                          : (productsList.isNotEmpty
                                ? productsList.first['id'] as int?
                                : null);

                      if (productsList.isEmpty) {
                        return Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.red.shade100),
                          ),
                          child: Text(
                            _tr(
                              'أضف بروفيل بارداش إلى هذه السيري وحدد عرضه الظاهر وسمكه وطول بارته ليتم الحساب.',
                            ),
                            style: TextStyle(fontSize: 9, color: Colors.red),
                          ),
                        );
                      }

                      return Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: Colors.grey.shade300),
                        ),
                        child: DropdownButtonHideUnderline(
                          child: DropdownButton<int>(
                            value: currentProductId,
                            isExpanded: true,
                            icon: const Icon(
                              Icons.arrow_drop_down,
                              color: Colors.blue,
                            ),
                            items: productsList.map((p) {
                              final name = p['name']?.toString() ?? 'بارداج';
                              final double dbVw =
                                  (p['visible_width'] as num?)?.toDouble() ??
                                  0.0;
                              final double dbThick =
                                  (p['thickness'] as num?)?.toDouble() ?? 24.0;
                              final double visibleW = dbVw > 0 ? dbVw : dbThick;
                              final double thickness = dbThick;
                              return DropdownMenuItem<int>(
                                value: p['id'] as int?,
                                child: Text(
                                  '$name - العرض: ${visibleW.toStringAsFixed(0)} مم (السمك: ${thickness.toStringAsFixed(0)} مم)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              );
                            }).toList(),
                            onChanged: (val) async {
                              if (val != null) {
                                final chosen = productsList.firstWhere(
                                  (p) => p['id'] == val,
                                );
                                final rawThickness = chosen['thickness'];
                                final profileThickness = rawThickness is num
                                    ? rawThickness.toDouble()
                                    : double.tryParse(
                                            rawThickness?.toString() ?? '',
                                          ) ??
                                          0.0;
                                final newSpec = spec.copyWith(
                                  panneauProductId: val,
                                  thicknessOuter: profileThickness,
                                );

                                if (chosen['is_profile'] == true) {
                                  final mutableChosen =
                                      Map<String, dynamic>.from(chosen);
                                  widget
                                          .model
                                          .componentOverrides['البارداج (Bardage)'] =
                                      mutableChosen;
                                  await widget.model
                                      .refreshBardageColorPrices();
                                } else {
                                  widget.model.componentOverrides.remove(
                                    'البارداج (Bardage)',
                                  );
                                }

                                if (zone != null) {
                                  widget.model.updateSelectedZoneGlass(
                                    panneauProductId: val,
                                    thicknessOuter: profileThickness,
                                  );
                                } else {
                                  _setViewState(() {
                                    _tempGlassSpec = newSpec;
                                  });
                                }
                                _startPaintbrushMode(glassSpec: newSpec);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 8),

                  // البارداج يأخذ ألوان البروفيلات (السيري)
                  Padding(
                    padding: EdgeInsets.only(top: 8, bottom: 8),
                    child: Text(
                      _tr('لون البارداج:'),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                  ),
                  Builder(
                    builder: (context) {
                      final colorList = widget.model.availableColors;
                      final frameColorName =
                          (widget.model.selectedDbColor?['name'] ??
                                  widget.model.selectedDbColor?['color_name'] ??
                                  widget.model.frameColor.name)
                              .toString()
                              .trim();
                      final effectiveColorName = widget.model
                          .getBardageColorNameForSpec(spec);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _HorizontalWheelScrollArea(
                            builder: (context, controller) =>
                                SingleChildScrollView(
                                  controller: controller,
                                  scrollDirection: Axis.horizontal,
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 4,
                                    ),
                                    child: Row(
                                      children: [
                                        Padding(
                                          padding: const EdgeInsets.only(
                                            right: 10,
                                          ),
                                          child: ChoiceChip(
                                            label: Text(
                                              '${_tr('تلقائي:')} $frameColorName',
                                              style: const TextStyle(
                                                fontSize: 9,
                                              ),
                                            ),
                                            avatar: const Icon(
                                              Icons.sync_rounded,
                                              size: 16,
                                            ),
                                            selected:
                                                spec.bardageUsesFrameColor,
                                            onSelected: (_) async {
                                              final newSpec = spec.copyWith(
                                                panneauColor: frameColorName,
                                                bardageUsesFrameColor: true,
                                              );
                                              if (zone != null) {
                                                await widget.model
                                                    .updateSelectedZoneGlass(
                                                      panneauColor:
                                                          frameColorName,
                                                      bardageUsesFrameColor:
                                                          true,
                                                    );
                                              } else {
                                                _setViewState(() {
                                                  _tempGlassSpec = newSpec;
                                                });
                                              }
                                              _startPaintbrushMode(
                                                glassSpec: newSpec,
                                              );
                                            },
                                          ),
                                        ),
                                        ...colorList.map((colorMap) {
                                          final colorName =
                                              (colorMap['name'] ??
                                                      colorMap['color_name'] ??
                                                      '')
                                                  .toString();
                                          final isSelected =
                                              !spec.bardageUsesFrameColor &&
                                              effectiveColorName
                                                      .toLowerCase() ==
                                                  colorName.toLowerCase();
                                          final woodImage =
                                              _getWoodTextureImage(colorMap);
                                          final parsedColor =
                                              getEffectiveGradientColors(
                                                FrameColor.white,
                                                colorMap,
                                              )[1];

                                          return Padding(
                                            padding: const EdgeInsets.only(
                                              right: 10,
                                            ),
                                            child: GestureDetector(
                                              onTap: () async {
                                                final newSpec = spec.copyWith(
                                                  panneauColor: colorName,
                                                  bardageUsesFrameColor: false,
                                                );
                                                if (zone != null) {
                                                  await widget.model
                                                      .updateSelectedZoneGlass(
                                                        panneauColor: colorName,
                                                        bardageUsesFrameColor:
                                                            false,
                                                      );
                                                } else {
                                                  _setViewState(() {
                                                    _tempGlassSpec = newSpec;
                                                  });
                                                }
                                                _startPaintbrushMode(
                                                  glassSpec: newSpec,
                                                );
                                              },
                                              child: Column(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Container(
                                                    width: isSelected ? 34 : 28,
                                                    height: isSelected
                                                        ? 34
                                                        : 28,
                                                    decoration: BoxDecoration(
                                                      shape: BoxShape.circle,
                                                      color: woodImage != null
                                                          ? null
                                                          : parsedColor,
                                                      image: woodImage,
                                                      border: Border.all(
                                                        color: isSelected
                                                            ? Colors.blue
                                                            : Colors
                                                                  .grey
                                                                  .shade400,
                                                        width: isSelected
                                                            ? 2.5
                                                            : 1.0,
                                                      ),
                                                      boxShadow: [
                                                        if (isSelected)
                                                          BoxShadow(
                                                            color: Colors.blue
                                                                .withOpacity(
                                                                  0.3,
                                                                ),
                                                            blurRadius: 4,
                                                            spreadRadius: 1,
                                                          ),
                                                      ],
                                                    ),
                                                  ),
                                                  const SizedBox(height: 4),
                                                  SizedBox(
                                                    width: 42,
                                                    child: Text(
                                                      colorName,
                                                      textAlign:
                                                          TextAlign.center,
                                                      maxLines: 2,
                                                      overflow:
                                                          TextOverflow.ellipsis,
                                                      style: TextStyle(
                                                        fontSize: 9,
                                                        fontWeight: isSelected
                                                            ? FontWeight.bold
                                                            : FontWeight.normal,
                                                        color: isSelected
                                                            ? Colors
                                                                  .blue
                                                                  .shade900
                                                            : Colors.black87,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          );
                                        }),
                                      ],
                                    ),
                                  ),
                                ),
                          ),
                          if (colorList.isEmpty)
                            Padding(
                              padding: EdgeInsets.only(bottom: 8),
                              child: Text(
                                _tr('لا توجد ألوان مضافة لهذه السلسلة.'),
                                style: TextStyle(
                                  fontSize: 9,
                                  color: Colors.red,
                                ),
                              ),
                            ),
                          const SizedBox(height: 12),
                          Text(
                            _tr('اتجاه شرائح البارداج:'),
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              Expanded(
                                child: _ContentButton(
                                  label: 'أفقي',
                                  icon: Icons.reorder_rounded,
                                  selected: !(spec.isVerticalBardage),
                                  onPressed: () {
                                    final newSpec = spec.copyWith(
                                      isVerticalBardage: false,
                                    );
                                    if (zone != null &&
                                        widget.model.activeSubZone != null) {
                                      widget.model.updateSelectedZoneGlass(
                                        isVerticalBardage: false,
                                      );
                                    } else {
                                      _setViewState(() {
                                        _tempGlassSpec = newSpec;
                                      });
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                  },
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: _ContentButton(
                                  label: 'عمودي',
                                  icon: Icons.view_week_rounded,
                                  selected: spec.isVerticalBardage,
                                  onPressed: () {
                                    final newSpec = spec.copyWith(
                                      isVerticalBardage: true,
                                    );
                                    if (zone != null &&
                                        widget.model.activeSubZone != null) {
                                      widget.model.updateSelectedZoneGlass(
                                        isVerticalBardage: true,
                                      );
                                    } else {
                                      _setViewState(() {
                                        _tempGlassSpec = newSpec;
                                      });
                                    }
                                    _startPaintbrushMode(glassSpec: newSpec);
                                  },
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 5,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.orange.shade50,
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(color: Colors.orange.shade200),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.view_stream_rounded,
                                  size: 12,
                                  color: Colors.orange,
                                ),
                                SizedBox(width: 4),
                                Text(
                                  _tr('يُحسب بالمتر الطولي كبروفيل'),
                                  style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.orange,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ] else if (structure == GlassStructure.double) ...[
                const Divider(),
                Text(
                  Localization.translate('الوجه الخارجي', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                buildGlassLayer(true),
                const SizedBox(height: 8),
                const Divider(),
                Text(
                  Localization.translate('الوجه الداخلي', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                buildGlassLayer(false),
                const SizedBox(height: 12),
                Text(
                  Localization.translate(
                    'سمك الفاصل (Intercall) — المقترح تلقائياً حسب Parclose:',
                    lang,
                  ),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 6),
                if (requiredIntercall == null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: Text(
                      _tr(
                        'لا توجد Parclose مناسبة لسماكة لوحي الزجاج المختارة. اختر Parclose مزدوجة متوافقة أولاً.',
                      ),
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: intercallChoices.map((g) {
                    int val = (g['thickness'] as num?)?.toInt() ?? 0;
                    final isSliding =
                        widget.systemMode == 'sliding' ||
                        widget.model.systemMode == 'sliding' ||
                        (zone != null &&
                            zone.content == ZoneContent.slidingSash);
                    final double tOuter =
                        spec.thicknessOuter ?? kDefaultGlassPaneThickness;
                    final double tInner =
                        spec.thicknessInner ?? kDefaultGlassPaneThickness;
                    final bool pvcBead = isSliding
                        ? widget.model.isSlidingPVC
                        : widget.model.isPVC;
                    // A PVC bead holds the panes without separate gaskets.
                    final double jointAllowance = pvcBead
                        ? 0.0
                        : isSliding
                        ? (widget.model.selectedVitrageJointThickness(
                                fallback: 2.0,
                              ) *
                              (spec.jointTwoSides ? 2 : 1))
                        : (widget.model.selectedVitrageJointThickness(
                                fallback: 2.0,
                              ) +
                              widget.model.selectedBourrageJointThickness(
                                doubleGlass: true,
                                fallback: 2.0,
                              ));
                    final maxCapacity = widget.model
                        .glazingCapacityForStructure(
                          GlassStructure.double,
                          sliding: isSliding,
                          glass: spec,
                        );
                    final totalWithJoint =
                        tOuter + val + tInner + jointAllowance;
                    // The pack may exceed the capacity by 1 mm at most.
                    final bool exceedsCapacity =
                        maxCapacity != null &&
                        totalWithJoint > maxCapacity + 1.000001;

                    return _IntercallButton(
                      thickness: val,
                      selected: spec.intercallThickness == val,
                      exceedsCapacity: exceedsCapacity,
                      showWarning:
                          widget.model.getPriceForIntercall(val) == 0.0,
                      onPressed: () async {
                        // The user may pick any spacer; an incompatible one
                        // is kept and reported (with a suggestion) instead
                        // of being refused or replaced silently.
                        final newSpec = spec.copyWith(
                          intercallThickness: val,
                          manualIntercall: true,
                        );
                        _startPaintbrushMode(glassSpec: newSpec);
                        if (zone == null) {
                          _setViewState(() {
                            _tempGlassSpec = newSpec;
                          });
                          return;
                        }
                        await widget.model.updateSelectedZoneGlass(
                          intercallThickness: val,
                          manualIntercall: true,
                        );
                        final report = widget.model.glazingFitReport;
                        if (!context.mounted ||
                            report == null ||
                            report.valid) {
                          return;
                        }
                        ScaffoldMessenger.of(context).hideCurrentSnackBar();
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              describeGlazingFit(
                                report,
                                Provider.of<AppSettingsProvider>(
                                  context,
                                  listen: false,
                                ).language,
                              ),
                            ),
                            backgroundColor: Colors.orange.shade800,
                            duration: const Duration(seconds: 5),
                          ),
                        );
                      },
                    );
                  }).toList(),
                ),
                Padding(
                  padding: const EdgeInsets.only(top: 8.0, bottom: 8.0),
                  child: Row(
                    children: [
                      const Icon(
                        Icons.air_rounded,
                        color: Colors.blue,
                        size: 18,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        _tr('يحتوي على غاز (Gas)'),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                      const Spacer(),
                      Switch(
                        value: spec.hasGas,
                        activeThumbColor: Colors.blue,
                        onChanged: (val) {
                          final newSpec = spec.copyWith(hasGas: val);
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlass(hasGas: val);
                          } else {
                            _setViewState(() {
                              _tempGlassSpec = newSpec;
                            });
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        },
                      ),
                    ],
                  ),
                ),
                const Divider(),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      Localization.translate(
                        'ديكور الزجاج المزدوج (ورود):',
                        lang,
                      ),
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                        fontSize: 12,
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          Localization.translate('وردات', lang),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Checkbox(
                          value: spec.hasRosettes,
                          activeColor: Colors.blue,
                          visualDensity: VisualDensity.compact,
                          onChanged: (val) {
                            if (val != null) {
                              final newSpec = spec.copyWith(hasRosettes: val);
                              if (zone != null) {
                                widget.model.updateSelectedZoneGlassDecor(
                                  hasRosettes: val,
                                );
                              } else {
                                _setViewState(() => _tempGlassSpec = newSpec);
                              }
                              _startPaintbrushMode(glassSpec: newSpec);
                            }
                          },
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Text(
                      Localization.translate('أفقي:', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: () {
                        if (spec.decorH > 0) {
                          final newSpec = spec.copyWith(
                            decorH: spec.decorH - 1,
                          );
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlassDecor(
                              decorH: newSpec.decorH,
                            );
                          } else {
                            _setViewState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        }
                      },
                    ),
                    Text(
                      '${spec.decorH}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () {
                        final newSpec = spec.copyWith(decorH: spec.decorH + 1);
                        if (zone != null) {
                          widget.model.updateSelectedZoneGlassDecor(
                            decorH: newSpec.decorH,
                          );
                        } else {
                          _setViewState(() => _tempGlassSpec = newSpec);
                        }
                        _startPaintbrushMode(glassSpec: newSpec);
                      },
                    ),
                  ],
                ),
                Row(
                  children: [
                    Text(
                      Localization.translate('عمودي:', lang),
                      style: const TextStyle(fontSize: 12),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.remove, size: 16),
                      onPressed: () {
                        if (spec.decorV > 0) {
                          final newSpec = spec.copyWith(
                            decorV: spec.decorV - 1,
                          );
                          if (zone != null) {
                            widget.model.updateSelectedZoneGlassDecor(
                              decorV: newSpec.decorV,
                            );
                          } else {
                            _setViewState(() => _tempGlassSpec = newSpec);
                          }
                          _startPaintbrushMode(glassSpec: newSpec);
                        }
                      },
                    ),
                    Text(
                      '${spec.decorV}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add, size: 16),
                      onPressed: () {
                        final newSpec = spec.copyWith(decorV: spec.decorV + 1);
                        if (zone != null) {
                          widget.model.updateSelectedZoneGlassDecor(
                            decorV: newSpec.decorV,
                          );
                        } else {
                          _setViewState(() => _tempGlassSpec = newSpec);
                        }
                        _startPaintbrushMode(glassSpec: newSpec);
                      },
                    ),
                  ],
                ),
                Builder(
                  builder: (context) {
                    final baguettes = widget.model.allGlassCache
                        .where(
                          (g) => g['type'].toString().toLowerCase().contains(
                            'baguette',
                          ),
                        )
                        .toList();

                    if (baguettes.isEmpty) {
                      return Padding(
                        padding: EdgeInsets.symmetric(vertical: 8.0),
                        child: Text(
                          _tr(
                            'لا يوجد باجيت ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                          ),
                          style: TextStyle(color: Colors.red, fontSize: 11),
                        ),
                      );
                    }

                    // Safe int id extraction
                    int? specBaguetteId = (spec.decorBaguetteId is int)
                        ? spec.decorBaguetteId as int
                        : int.tryParse(spec.decorBaguetteId?.toString() ?? '');

                    var selectedBaguette = baguettes.firstWhere(
                      (b) => (b['id'] as num?)?.toInt() == specBaguetteId,
                      orElse: () => baguettes.first,
                    );

                    final int selectedBaguetteId =
                        (selectedBaguette['id'] as num?)?.toInt() ??
                        (baguettes.first['id'] as num?)?.toInt() ??
                        0;

                    List<String> allowedColors = widget.model.allGlassCache
                        .where(
                          (g) =>
                              (g['id'] as num?)?.toInt() == selectedBaguetteId,
                        )
                        .map((g) => g['color']?.toString() ?? '')
                        .where((c) => c.isNotEmpty)
                        .toList();
                    if (allowedColors.isEmpty) {
                      allowedColors = ['أبيض', 'ذهبي', 'فضي', 'رمادي'];
                    }

                    String currentDecorColor = spec.decorColor;
                    if (!allowedColors.contains(currentDecorColor)) {
                      currentDecorColor = allowedColors.first;
                    }

                    // Build unique items lists (no duplicate ids)
                    final List<int> baguetteIds = [];
                    final List<Map<String, dynamic>> uniqueBaguettes = [];
                    for (final b in baguettes) {
                      final id = (b['id'] as num?)?.toInt();
                      if (id != null && !baguetteIds.contains(id)) {
                        baguetteIds.add(id);
                        uniqueBaguettes.add(b);
                      }
                    }

                    // Ensure selected value is in list
                    final int safeSelectedId =
                        baguetteIds.contains(selectedBaguetteId)
                        ? selectedBaguetteId
                        : (baguetteIds.isNotEmpty ? baguetteIds.first : 0);

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text(
                              Localization.translate('نوع الباجيت:', lang),
                              style: TextStyle(fontSize: 12),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<int>(
                                  isExpanded: true,
                                  value: safeSelectedId,
                                  items: uniqueBaguettes.map((b) {
                                    final id = (b['id'] as num?)?.toInt() ?? 0;
                                    return DropdownMenuItem<int>(
                                      value: id,
                                      child: Text(
                                        '${b['name']} (${b['thickness']} مم)',
                                        style: const TextStyle(fontSize: 12),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    );
                                  }).toList(),
                                  onChanged: (val) {
                                    if (val != null) {
                                      final newBaguette = uniqueBaguettes
                                          .firstWhere(
                                            (b) =>
                                                (b['id'] as num?)?.toInt() ==
                                                val,
                                            orElse: () => uniqueBaguettes.first,
                                          );
                                      final double newThickness =
                                          (newBaguette['thickness'] as num?)
                                              ?.toDouble() ??
                                          0.0;
                                      final allowedColorsList =
                                          (newBaguette['color']?.toString() ??
                                                  '')
                                              .split(',')
                                              .map((c) => c.trim())
                                              .where((c) => c.isNotEmpty)
                                              .toList();
                                      final String newColor =
                                          allowedColorsList.isNotEmpty
                                          ? allowedColorsList.first
                                          : 'أبيض';

                                      final newSpec = spec.copyWith(
                                        decorBaguetteId: val,
                                        decorThickness: newThickness,
                                        decorColor: newColor,
                                      );

                                      if (zone != null) {
                                        widget.model
                                            .updateSelectedZoneGlassDecor(
                                              decorBaguetteId: val,
                                              decorThickness: newThickness,
                                              decorColor: newColor,
                                            );
                                      } else {
                                        _setViewState(
                                          () => _tempGlassSpec = newSpec,
                                        );
                                      }
                                      _startPaintbrushMode(glassSpec: newSpec);
                                    }
                                  },
                                ),
                              ),
                            ),
                          ],
                        ),
                        Row(
                          children: [
                            Text(
                              Localization.translate('اللون:', lang),
                              style: TextStyle(fontSize: 12),
                            ),
                            const Spacer(),
                            DropdownButton<String>(
                              value: currentDecorColor,
                              items: allowedColors.map((colorName) {
                                return DropdownMenuItem<String>(
                                  value: colorName,
                                  child: Text(
                                    colorName,
                                    style: const TextStyle(fontSize: 12),
                                  ),
                                );
                              }).toList(),
                              onChanged: (val) {
                                if (val != null) {
                                  final newSpec = spec.copyWith(
                                    decorColor: val,
                                  );
                                  if (zone != null) {
                                    widget.model.updateSelectedZoneGlassDecor(
                                      decorColor: val,
                                    );
                                  } else {
                                    _setViewState(() => _tempGlassSpec = newSpec);
                                  }
                                  _startPaintbrushMode(glassSpec: newSpec);
                                }
                              },
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
                if (spec.hasRosettes) ...[
                  const SizedBox(height: 8),
                  Builder(
                    builder: (context) {
                      final rosettes = widget.model.allGlassCache
                          .where(
                            (g) => g['type'].toString().toLowerCase().contains(
                              'rosette',
                            ),
                          )
                          .toList();

                      if (rosettes.isEmpty) {
                        return Padding(
                          padding: EdgeInsets.symmetric(vertical: 4.0),
                          child: Text(
                            Localization.translate(
                              'لا توجد وردات ديكور في قاعدة البيانات. يرجى إضافتها أولاً.',
                              lang,
                            ),
                            style: TextStyle(color: Colors.red, fontSize: 11),
                          ),
                        );
                      }

                      // Safe int id extraction for rosette
                      int? specRosetteId = (spec.decorRosetteId is int)
                          ? spec.decorRosetteId as int
                          : int.tryParse(spec.decorRosetteId?.toString() ?? '');

                      // Build unique rosette items (no duplicate ids)
                      final List<int> rosetteIds = [];
                      final List<Map<String, dynamic>> uniqueRosettes = [];
                      for (final r in rosettes) {
                        final id = (r['id'] as num?)?.toInt();
                        if (id != null && !rosetteIds.contains(id)) {
                          rosetteIds.add(id);
                          uniqueRosettes.add(r);
                        }
                      }

                      var selectedRosette = uniqueRosettes.firstWhere(
                        (r) => (r['id'] as num?)?.toInt() == specRosetteId,
                        orElse: () => uniqueRosettes.first,
                      );

                      final int selectedRosetteId =
                          (selectedRosette['id'] as num?)?.toInt() ??
                          (rosetteIds.isNotEmpty ? rosetteIds.first : 0);

                      final int safeRosetteId =
                          rosetteIds.contains(selectedRosetteId)
                          ? selectedRosetteId
                          : (rosetteIds.isNotEmpty ? rosetteIds.first : 0);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                _tr('نوع الوردة:'),
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: safeRosetteId,
                                    items: uniqueRosettes.map((r) {
                                      final id =
                                          (r['id'] as num?)?.toInt() ?? 0;
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Text(
                                          r['name'].toString(),
                                          style: const TextStyle(fontSize: 12),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (val) {
                                      if (val != null) {
                                        final newSpec = spec.copyWith(
                                          decorRosetteId: val,
                                        );
                                        if (zone != null) {
                                          widget.model
                                              .updateSelectedZoneGlassDecor(
                                                decorRosetteId: val,
                                              );
                                        } else {
                                          _setViewState(
                                            () => _tempGlassSpec = newSpec,
                                          );
                                        }
                                        _startPaintbrushMode(
                                          glassSpec: newSpec,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const Text(
                                'شكل الوردة:',
                                style: TextStyle(fontSize: 12),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    isExpanded: true,
                                    value: spec.rosetteShape,
                                    items: [
                                      DropdownMenuItem(
                                        value: 1,
                                        child: Text(
                                          _tr('شكل 1 (نجمة)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 2,
                                        child: Text(
                                          _tr('شكل 2 (منحني)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 3,
                                        child: Text(
                                          _tr('شكل 3 (باروكي)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 4,
                                        child: Text(
                                          _tr('شكل 4 (معين مصمت)'),
                                          style: TextStyle(fontSize: 12),
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        final newSpec = spec.copyWith(
                                          rosetteShape: val,
                                        );
                                        if (zone != null) {
                                          widget.model
                                              .updateSelectedZoneGlassDecor(
                                                rosetteShape: val,
                                              );
                                        } else {
                                          _setViewState(
                                            () => _tempGlassSpec = newSpec,
                                          );
                                        }
                                        _startPaintbrushMode(
                                          glassSpec: newSpec,
                                        );
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ],
              ] else ...[
                const SizedBox(height: 8),
                buildGlassLayer(true),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildDrawerContent(BuildContext context) {
    return ScrollConfiguration(
      behavior: _drawerScrollBehavior(context),
      child: ListenableBuilder(
        listenable: widget.model,
        builder: (context, _) {
          final lang = Provider.of<AppSettingsProvider>(context).language;
          final slidingZones = widget.model.zones
              .where((z) => z.content == ZoneContent.slidingSash)
              .toList();
          // The drawer must edit the selected sliding zone. Using the first
          // sliding zone left Slim enabled on the actual selected sash, so
          // unchecking it appeared to do nothing in the drawing.
          final selectedZone = widget.model.selectedZone;
          final firstSlidingZone =
              selectedZone?.content == ZoneContent.slidingSash
              ? selectedZone
              : (slidingZones.isNotEmpty ? slidingZones.first : null);
          final int sashesCount = firstSlidingZone?.slidingSashesCount ?? 2;
          final bool hasMeetingInCenter =
              (firstSlidingZone?.slidingFaceToFace ?? false) &&
              firstSlidingZone != null &&
              isSlidingFaceToFaceLayout(
                trackCount: firstSlidingZone.slidingTrackCount,
                sashCount: sashesCount,
              );
          final centralKeys = firstSlidingZone == null
              ? const <String>[]
              : slidingCentralEdgeKeys(
                  zone: firstSlidingZone,
                  sashesCount: sashesCount,
                );
          final int centralCount = centralKeys.length;

          // دالة مساعدة لرسم الـ Checkbox ملتصقاً بنصه
          Widget buildCompactOption(String label, String key, WindowZone zone) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: zone.slidingMontantReinforced[key] ?? false,
                  onChanged: (v) {
                    _setViewState(() {
                      zone.slidingMontantReinforced[key] = v ?? false;
                    });
                    unawaited(
                      _syncSlidingMontantOverrideFromFlags(
                        central: key.startsWith('central_'),
                      ),
                    );
                  },
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            );
          }

          Widget buildCompactSlimOption(
            String label,
            String key,
            WindowZone zone,
          ) {
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Checkbox(
                  value: zone.slidingMontantSlim[key] ?? false,
                  onChanged: (v) {
                    _setViewState(() {
                      final enabled = v ?? false;
                      if (enabled) {
                        zone.slidingMontantSlim[key] = true;
                      } else {
                        // Removing the key is important: stale saved keys can
                        // otherwise keep the Slim geometry alive.
                        zone.slidingMontantSlim.remove(key);
                      }
                      if (zone.slidingMontantSlim[key] == true &&
                          widget.model.selectedSlimMontantProfile == null) {
                        final candidates = widget.model
                            .getSlidingSlimCandidates();
                        if (candidates.isNotEmpty) {
                          widget.model.applySlidingMontantSlimOverride(
                            candidates.first,
                          );
                        }
                      }
                    });
                    widget.model.clearSlidingMontantSlimOverrideIfInactive();
                    widget.model.refreshUI();
                  },
                  activeColor: Colors.blue,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Text(label, style: const TextStyle(fontSize: 12)),
              ],
            );
          }

          return ListView(
            controller: _rightDrawerScrollController,
            padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
            children: [
              // 🟢 1. الخصائص العامة
              Row(
                children: [
                  Icon(Icons.tune_rounded, color: Colors.blue.shade800),
                  const SizedBox(width: 8),
                  Text(
                    Localization.translate('الخصائص العامة', lang),
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ],
              ),
              const Divider(height: 20),

              DropdownButtonFormField<bool>(
                key: ValueKey(_showAllFrameProfiles),
                initialValue: _showAllFrameProfiles,
                isDense: true,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: Localization.translate('عرض الإطارات', lang),
                  prefixIcon: const Icon(Icons.view_carousel_outlined),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 8,
                  ),
                ),
                items: [
                  DropdownMenuItem<bool>(
                    value: false,
                    child: Text(
                      Localization.translate('الإطارات الصالحة فقط', lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  DropdownMenuItem<bool>(
                    value: true,
                    child: Text(
                      Localization.translate('كل إطارات السلسلة', lang),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    unawaited(_setShowAllFrameProfiles(value));
                  }
                },
              ),
              const SizedBox(height: 15),

              TextField(
                controller: _positionCtrl,
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'موقع النافذة (مثال: المطبخ - الطابق 2)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.location_on),
                ),
                style: const TextStyle(fontSize: 13),
                onChanged: (val) {
                  widget.model.position = val;
                },
              ),
              const SizedBox(height: 15),

              GestureDetector(
                onTap: () {
                  widget.model.toggleViewMode();
                  _setViewState(() {});
                },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: widget.model.isInternalView
                        ? (Theme.of(context).brightness == Brightness.dark
                              ? Colors.blue.shade900.withValues(alpha: 0.3)
                              : Colors.blue.shade50)
                        : (Theme.of(context).brightness == Brightness.dark
                              ? Colors.orange.shade900.withValues(alpha: 0.3)
                              : Colors.orange.shade50),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: widget.model.isInternalView
                          ? Colors.blue
                          : Colors.orange,
                      width: 1.5,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        widget.model.isInternalView
                            ? Icons.visibility
                            : Icons.flip_camera_android,
                        size: 20,
                        color: widget.model.isInternalView
                            ? (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.blue.shade300
                                  : Colors.blue.shade900)
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.orange.shade300
                                  : Colors.orange.shade900),
                      ),
                      const SizedBox(width: 10),
                      Text(
                        widget.model.isInternalView
                            ? Localization.translate('مشاهدة: وجه داخلي', lang)
                            : Localization.translate('مشاهدة: وجه خارجي', lang),
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: widget.model.isInternalView
                              ? (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.blue.shade300
                                    : Colors.blue.shade900)
                              : (Theme.of(context).brightness == Brightness.dark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade900),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (!widget.model.isInternalView)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                  secondary: const Icon(Icons.handyman_outlined),
                  title: Text(
                    Localization.translate(
                      'إظهار المقابض والمفاصل والتجاويف في الوجه الخارجي',
                      lang,
                    ),
                    style: const TextStyle(fontSize: 13),
                  ),
                  value: widget.model.showInternalHardware,
                  onChanged: widget.model.setInternalHardwareVisibility,
                ),
              const SizedBox(height: 20),

              Text(
                widget.model.selectedDbColor != null
                    ? '${Localization.translate('اللون:', lang)} ${Localization.translate((widget.model.selectedDbColor!['name'] ?? '').toString(), lang)}'
                    : Localization.translate('لون الألمنيوم', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children:
                    widget.model.colorsLoading &&
                        widget.model.availableColors.isEmpty
                    ? const [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ]
                    : widget.model.availableColors.map((dbColor) {
                        final isSelected =
                            widget.model.selectedDbColor != null &&
                            widget.model.selectedDbColor!['id'] ==
                                dbColor['id'];
                        Color parsedColor = getEffectiveGradientColors(
                          FrameColor.white,
                          dbColor,
                        )[1];
                        final woodImage = _getWoodTextureImage(dbColor);
                        return GestureDetector(
                          onTap: () {
                            widget.model.selectProfileColorWithDefaults(
                              dbColor,
                            );
                            widget.model.refreshUI();
                          },
                          child: Container(
                            width: isSelected ? 30 : 25,
                            height: isSelected ? 30 : 25,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: woodImage != null ? null : parsedColor,
                              image: woodImage,
                              border: Border.all(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade400,
                                width: isSelected ? 2.5 : 1.0,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
              ),
              const SizedBox(height: 15),

              Text(
                widget.model.selectedAccessoryColor != null
                    ? '${Localization.translate('لون الإكسسوارات:', lang)} ${Localization.translate((widget.model.selectedAccessoryColor!['name'] ?? '').toString(), lang)}'
                    : Localization.translate('لون الإكسسوارات (افتراضي)', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: widget.model.availableAccessoryColors.map((dbColor) {
                  final isSelected =
                      widget.model.selectedAccessoryColor != null &&
                      widget.model.selectedAccessoryColor!['id'] ==
                          dbColor['id'];
                  Color parsedColor = getEffectiveGradientColors(
                    FrameColor.white,
                    dbColor,
                  )[1];
                  final woodImage = _getWoodTextureImage(dbColor);
                  return GestureDetector(
                    onTap: () {
                      if (isSelected) {
                        widget.model.selectedAccessoryColor = null;
                      } else {
                        widget.model.selectedAccessoryColor = dbColor;
                      }
                      widget.model.refreshUI();
                    },
                    child: Container(
                      width: isSelected ? 30 : 25,
                      height: isSelected ? 30 : 25,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: woodImage != null ? null : parsedColor,
                        image: woodImage,
                        border: Border.all(
                          color: isSelected
                              ? Colors.blue
                              : Colors.grey.shade400,
                          width: isSelected ? 2.5 : 1.0,
                        ),
                      ),
                    ),
                  );
                }).toList(),
              ),

              if (widget.model.systemMode != 'sliding')
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('إطار سفلي', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.selectedFrameHasBottom,
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.canEditSelectedBottomFrame
                      ? (value) => widget.model.toggleBottomFrame(value)
                      : null,
                ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(
                  Localization.translate('رسم الجدار', lang),
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                value: widget.model.showWall,
                activeThumbColor: Colors.blue,
                onChanged: (value) => widget.model.toggleShowWall(value),
              ),
              if (widget.model.showWall) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _tr('لون الجدار'),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        children: [
                          // Red wall color option
                          GestureDetector(
                            onTap: () => widget.model.toggleWallColor('red'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.model.wallColor == 'red'
                                    ? Colors.red.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.model.wallColor == 'red'
                                      ? Colors.red
                                      : Colors.grey.shade300,
                                  width: widget.model.wallColor == 'red'
                                      ? 2
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFFC85A3F),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    _tr('أحمر'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Grey wall color option
                          GestureDetector(
                            onTap: () => widget.model.toggleWallColor('grey'),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: widget.model.wallColor == 'grey'
                                    ? Colors.grey.withValues(alpha: 0.15)
                                    : Colors.transparent,
                                border: Border.all(
                                  color: widget.model.wallColor == 'grey'
                                      ? Colors.grey.shade700
                                      : Colors.grey.shade300,
                                  width: widget.model.wallColor == 'grey'
                                      ? 2
                                      : 1,
                                ),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 12,
                                    height: 12,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8A939E),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  const Text(
                                    'رمادي 9007',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
              ],
              (() {
                return SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('غطاء جانبي', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.hasSideCovers,
                  activeThumbColor: Colors.blue,
                  // The user may always explicitly enable or disable the
                  // couvre-joint. Catalogue capability rules control the
                  // default/profile choice, never the switch availability.
                  onChanged: (value) {
                    if (value != null) {
                      widget.model.toggleSideCovers(value);
                    }
                  },
                );
              }()),
              if (widget.model.hasSideCovers) ...[
                if ((widget.model.getSectionByType('frame')?.couvreJointWidth ??
                            0) ==
                        0 &&
                    widget.model.canUseStandaloneSideCover &&
                    widget.model.availableSideCovers.length > 1)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اختر الغطاء الجانبي',
                          lang,
                        ),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 8,
                        ),
                      ),
                      value:
                          widget.model.availableSideCovers.any(
                            (c) => c.id == widget.model.selectedSideCover?.id,
                          )
                          ? widget.model.selectedSideCover?.id
                          : widget.model.availableSideCovers.first.id,
                      items: widget.model.availableSideCovers.map((cover) {
                        return DropdownMenuItem<int>(
                          value: cover.id,
                          child: Text(
                            cover.name,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          _setViewState(() {
                            widget.model.selectedSideCover = widget
                                .model
                                .availableSideCovers
                                .firstWhere((c) => c.id == val);
                            widget.model.sideCoverOverride = widget
                                .model
                                .selectedSideCover!
                                .toMap();
                            widget.model.refreshUI();
                          });
                        }
                      },
                    ),
                  ),
                Padding(
                  padding: const EdgeInsets.only(right: 10),
                  child: buildSideCoverSegmentsControl(
                    context,
                    widget.model,
                    lang,
                  ),
                ),
                // زر تبديل اتجاه الغطاء الجانبي — يظهر فقط إذا كان للمقطع اتجاهان والإطار بدون كفر جو مدمج
                if (widget.model.integratedFrameSideCoverWidth == 0 &&
                    (widget.model.selectedSideCover?.couvreJointWidth ?? 0) >
                        0 &&
                    ((widget.model.selectedSideCover?.visibleWidth ?? 0) > 0 ||
                        (widget.model.selectedSideCover?.visibleWidth2 ?? 0) >
                            0))
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 4),
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        side: BorderSide(color: Colors.blue.shade300),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      onPressed: () =>
                          widget.model.toggleSideCoverOrientation(),
                      icon: Icon(
                        Icons.swap_horiz,
                        size: 16,
                        color: Colors.blue.shade700,
                      ),
                      label: Text(
                        (() {
                          final cover = widget.model.selectedSideCover!;
                          final secondWidth = cover.visibleWidth > 0
                              ? cover.visibleWidth
                              : cover.visibleWidth2;
                          final width = widget.model.sideCoverUseSecondWidth
                              ? secondWidth
                              : cover.couvreJointWidth;
                          return '${width.toStringAsFixed(0)} mm';
                        })(),
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.blue.shade700,
                        ),
                      ),
                    ),
                  ),
              ],
              if (!widget.model.isShutterOnly)
                (() {
                  final isArchedOrSlanted =
                      widget.model.archHeight > 0 ||
                      widget.model.topSlantLeftY != 0 ||
                      widget.model.topSlantRightY != 0;
                  return SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate('الستار', lang),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    subtitle: isArchedOrSlanted
                        ? Text(
                            Localization.translate(
                              'الستار غير مدعوم للأشكال المقوسة أو المائلة',
                              lang,
                            ),
                            style: const TextStyle(
                              color: Colors.red,
                              fontSize: 11,
                            ),
                          )
                        : null,
                    value: widget.model.hasShutter,
                    activeThumbColor: Colors.blue,
                    onChanged: isArchedOrSlanted
                        ? null
                        : (value) => widget.model.toggleShutter(value),
                  );
                }()),

              if (!widget.model.isShutterOnly)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('الموستيكير', lang),
                    style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  subtitle: Text(
                    Localization.translate(
                    'تظهر في الكمية والتكلفة فقط ولا تظهر في الرسم',
                      lang,
                    ),
                    style: const TextStyle(fontSize: 11),
                  ),
                  value: widget.model.hasMoustiquaireAddon,
                  activeThumbColor: Colors.green,
                  onChanged: (_) => _toggleMoustiquaireAddon(),
                ),

              if (widget.model.hasShutter) ...[
                if (widget.model.shutterHeightWarning != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      border: Border.all(color: Colors.red.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.warning_amber_rounded,
                          color: Colors.red.shade700,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            widget.model.shutterHeightWarning!,
                            style: TextStyle(
                              color: Colors.red.shade900,
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (widget.model.shutterWidthWarning != null)
                  Container(
                    width: double.infinity,
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.orange.shade50,
                      border: Border.all(color: Colors.orange.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Icons.straighten,
                              color: Colors.orange.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                widget.model.localizedShutterWidthWarning(
                                      lang,
                                    ) ??
                                    widget.model.shutterWidthWarning!,
                                style: TextStyle(
                                  color: Colors.orange.shade900,
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (widget.model.recommendedShutterBlade != null) ...[
                          const SizedBox(height: 8),
                          Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.orange.shade800,
                                foregroundColor: Colors.white,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 4,
                                ),
                                visualDensity: VisualDensity.compact,
                              ),
                              icon: const Icon(
                                Icons.check_circle_outline,
                                size: 14,
                              ),
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
                                await widget.model
                                    .updateShutterDefaultsIfNeeded();
                                if (mounted) _setViewState(() {});
                              },
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate(
                      'صندوق النفق (Caisson tunnel)',
                      lang,
                    ),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.isCaissonTunnel,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleCaissonTunnel(value);
                  },
                ),
                if (widget.model.isCaissonTunnel) ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0, bottom: 4.0),
                    child: Text(
                      Localization.translate(
                        'ارتفاع Caisson Tunnel (Hauteur Tunnel):',
                        lang,
                      ),
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ContentButton(
                        label: '25 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 250.0,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.setCaissonTunnelHeight(250.0);
                          });
                        },
                      ),
                      _ContentButton(
                        label: '30 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 300.0,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.setCaissonTunnelHeight(300.0);
                          });
                        },
                      ),
                      _ContentButton(
                        label: '40 سم',
                        icon: Icons.straighten,
                        selected: widget.model.caissonTunnelHeight == 400.0,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.setCaissonTunnelHeight(400.0);
                          });
                        },
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                ],
                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('نوع الستار (Mechanism):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ContentButton(
                      label: 'حزام (Sangle)',
                      icon: Icons.line_weight,
                      selected: widget.model.shutterMechanism == 'حزام',
                      onPressed: () => _setShutterMechanismFeature('حزام'),
                    ),
                    _ContentButton(
                      label: 'منايفال (Manivelle)',
                      icon: Icons.rotate_right,
                      selected: widget.model.shutterMechanism == 'منايفال',
                      onPressed: () => _setShutterMechanismFeature('منايفال'),
                    ),
                    _ContentButton(
                      label: 'محرك (Moteur)',
                      icon: Icons.electrical_services,
                      selected: widget.model.shutterMechanism == 'محرك',
                      onPressed: () => _setShutterMechanismFeature('محرك'),
                    ),
                  ],
                ),

                if (widget.model.shutterMechanism == 'محرك') ...[
                  Padding(
                    padding: EdgeInsets.only(top: 10, bottom: 5),
                    child: Text(
                      _tr('خيارات المحرك:'),
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      _ContentButton(
                        label: 'قاطعة (Interrupteur)',
                        icon: Icons.power,
                        selected: widget.model.motorHasInterrupteur,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.motorHasInterrupteur =
                                !widget.model.motorHasInterrupteur;
                            widget.model.refreshUI();
                          });
                        },
                      ),
                      _ContentButton(
                        label: 'جهاز تحكم (Télécommande)',
                        icon: Icons.settings_remote,
                        selected: widget.model.motorHasTelecommande,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.motorHasTelecommande =
                                !widget.model.motorHasTelecommande;
                            widget.model.refreshUI();
                          });
                        },
                      ),
                    ],
                  ),
                ],

                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('جهة الستار (Drive Side):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    _ContentButton(
                      label: 'يمين (Droite)',
                      icon: Icons.keyboard_double_arrow_right,
                      selected: widget.model.shutterDriveSide == 'right',
                      onPressed: () {
                        _setViewState(() => widget.model.shutterDriveSide = 'right');
                        widget.model.refreshUI();
                      },
                    ),
                    _ContentButton(
                      label: 'يسار (Gauche)',
                      icon: Icons.keyboard_double_arrow_left,
                      selected: widget.model.shutterDriveSide == 'left',
                      onPressed: () {
                        _setViewState(() => widget.model.shutterDriveSide = 'left');
                        widget.model.refreshUI();
                      },
                    ),
                  ],
                ),

                Padding(
                  padding: const EdgeInsets.only(top: 10, bottom: 5),
                  child: Text(
                    Localization.translate('وضع الستار (Position):', lang),
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Slider(
                  value: widget.model.shutterPosition,
                  label: "${(widget.model.shutterPosition * 100).toInt()}%",
                  onChanged: (value) {
                    widget.model.setShutterPosition(value);
                  },
                ),
                const SizedBox(height: 10),
                _ContentButton(
                  label: widget.model.isShutterSplit
                      ? '${Localization.translate('فصل الصناديق', lang)} (${widget.model.effectiveShutterSplits.length})'
                      : Localization.translate('فصل الصناديق', lang),
                  icon: Icons.view_column_rounded,
                  selected: widget.model.isShutterSplit,
                  onPressed: () => _showSplitShutterDialog(context),
                ),
              ],

              const Divider(height: 20),

              if (!widget.model.isPVC &&
                  widget.model.canUseOpeningOnlyOptions &&
                  widget.model.hasPlintheSupport) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('استخدام بلانت أسفل الضلفة', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.hasFramePlintheBottom,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleFramePlintheBottom(value);
                  },
                ),
              ],

              if (widget.model.hasFrameRole('seuil'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(Localization.translate('Seuil (بروفيل C)', lang)),
                  subtitle: Text(
                    widget.model.frameRoleRequiredInAllScopes('seuil')
                        ? Localization.translate(
                            'مفعل حتميًا حسب قواعد السلسلة',
                            lang,
                          )
                        : Localization.translate('يستبدل الإطار السفلي', lang),
                  ),
                  value: widget.model.frameRoleEnabledInAnyScope('seuil'),
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.frameRoleRequiredInAllScopes('seuil')
                      ? null
                      : widget.model.toggleSeuil,
                ),

              if (widget.model.hasCaniveauSupport)
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate(
                      'تفعيل الكانيفو (Système C zéro)',
                      lang,
                    ),
                  ),
                  subtitle: Text(
                    widget.model.frameRoleEnabledInAnyScope('seuil')
                        ? Localization.translate(
                            'غير متاح مع بروفيل C / Seuil',
                            lang,
                          )
                        : Localization.translate(
                            'يتطلب الإطار السفلي ويضيف الغطاء والبوشون تلقائياً',
                            lang,
                          ),
                  ),
                  value: widget.model.useOptionalCaniveau,
                  activeThumbColor: Colors.blue,
                  onChanged:
                      widget.model.frameRoleEnabledInAnyScope('seuil') ||
                          !widget.model.canEnableCaniveau
                      ? null
                      : widget.model.toggleCaniveau,
                ),

              if (widget.model.hasBavetteSupport)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(Localization.translate('البافيت (Bavette)', lang)),
                      const SizedBox(height: 4),
                      ToggleButtons(
                        isSelected: [0, 1, 2]
                            .map(
                              (mode) =>
                                  widget.model.optionalBavetteMode == mode,
                            )
                            .toList(),
                        onPressed: widget.model.setOptionalBavetteMode,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(Localization.translate('إيقاف', lang)),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              Localization.translate('أسفل فقط', lang),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 10),
                            child: Text(
                              Localization.translate('الجهات الأربع', lang),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),

              if (widget.model.hasFrameRole('cache_dormant'))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('كاش الإطار (Cache dormant)', lang),
                  ),
                  subtitle: Text(
                    widget.model.frameRoleRequiredInAllScopes('cache_dormant')
                        ? Localization.translate(
                            'مفعل حتميًا حسب قواعد السلسلة',
                            lang,
                          )
                        : Localization.translate(
                            'يتبع فقط جهات الإطار الموجودة',
                            lang,
                          ),
                  ),
                  value: widget.model.frameRoleEnabledInAnyScope(
                    'cache_dormant',
                  ),
                  activeThumbColor: Colors.blue,
                  onChanged:
                      widget.model.frameRoleRequiredInAllScopes('cache_dormant')
                      ? null
                      : widget.model.toggleCacheDormant,
                ),

              if (widget.model.hasOptionalTriangleLink &&
                  (widget.model.getConfiguredSectionForRole('triangle') !=
                          null ||
                      widget.model.getConfiguredSectionForRole(
                            'triangle',
                            useSlidingSeries: true,
                          ) !=
                          null))
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('تراينغل (Triangle)', lang),
                  ),
                  subtitle: Text(
                    Localization.translate(
                      'استعمال اختياري حسب ربط الأكسيسوار',
                      lang,
                    ),
                  ),
                  value: widget.model.useOptionalTriangle,
                  activeThumbColor: Colors.blue,
                  onChanged: widget.model.toggleOptionalTriangle,
                ),

              Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          Localization.translate(
                            "بروفيل الزاوية 90° (Tube carré)",
                            lang,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        TextButton.icon(
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                          icon: const Icon(Icons.settings, size: 14),
                          label: Text(
                            Localization.translate('تخصيص', lang),
                            style: const TextStyle(fontSize: 11),
                          ),
                          onPressed: () => _showProfileAngleDialog(context),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final junctions = widget.model
                            .getAdjacentFrameJunctions();
                        if (junctions.isNotEmpty) {
                          final active =
                              widget.model.activeProfileAngleJunctions;
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Wrap(
                                spacing: 6,
                                runSpacing: 4,
                                children: junctions.map((j) {
                                  final isSel = active.contains(j.index);
                                  return FilterChip(
                                    label: Text(
                                      j.localizedLabel(lang),
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: isSel
                                            ? FontWeight.bold
                                            : FontWeight.normal,
                                      ),
                                    ),
                                    selected: isSel,
                                    onSelected: (val) {
                                      _setViewState(() {
                                        widget.model.toggleProfileAngleJunction(
                                          j.index,
                                          val,
                                        );
                                      });
                                    },
                                  );
                                }).toList(),
                              ),
                              const SizedBox(height: 4),
                              Row(
                                children: [
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      Localization.translate('الكل', lang),
                                      style: const TextStyle(fontSize: 11),
                                    ),
                                    onPressed: () {
                                      _setViewState(() {
                                        widget.model
                                            .setAllProfileAngleJunctions(true);
                                      });
                                    },
                                  ),
                                  const SizedBox(width: 8),
                                  TextButton(
                                    style: TextButton.styleFrom(
                                      padding: EdgeInsets.zero,
                                      minimumSize: Size.zero,
                                      tapTargetSize:
                                          MaterialTapTargetSize.shrinkWrap,
                                    ),
                                    child: Text(
                                      Localization.translate('إلغاء', lang),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        color: Colors.red,
                                      ),
                                    ),
                                    onPressed: () {
                                      _setViewState(() {
                                        widget.model
                                            .setAllProfileAngleJunctions(false);
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          );
                        }
                        return ToggleButtons(
                          isSelected: [0, 1, 2, 3]
                              .map(
                                (mode) => widget.model.profileAngleMode == mode,
                              )
                              .toList(),
                          onPressed: (index) {
                            _setViewState(() {
                              widget.model.setProfileAngleMode(index);
                            });
                          },
                          children: [
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                Localization.translate('إيقاف', lang),
                              ),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(Localization.translate('يمين', lang)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(Localization.translate('يسار', lang)),
                            ),
                            Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                              ),
                              child: Text(
                                Localization.translate('الجهتين', lang),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),

              if (widget.model.getConfiguredSectionForRole(
                    'cache_rail',
                    useSlidingSeries: true,
                  ) !=
                  null)
                Builder(
                  builder: (context) {
                    final tracks = widget.model.zones
                        .where(
                          (zone) => zone.content == ZoneContent.slidingSash,
                        )
                        .fold<int>(
                          2,
                          (current, zone) => math.max(
                            current,
                            zone.slidingTrackCount > 0
                                ? zone.slidingTrackCount
                                : zone.slidingSashesCount,
                          ),
                        );
                    final maximum = math.max(0, tracks - 1);
                    final enabled = widget.model.useOptionalCacheRail;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'كاش راي (Cache-rail)',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SwitchListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(enabled ? 'مفعّل' : 'غير مفعّل'),
                          subtitle: Text(
                            enabled
                                ? '$tracks سكك: $maximum يمين + $maximum يسار'
                                : '$tracks سكك: لا توجد قطع كاش راي',
                          ),
                          value: enabled,
                          activeThumbColor: Colors.blue,
                          onChanged: widget.model.toggleCacheRail,
                        ),
                      ],
                    );
                  },
                ),

              if (widget.model.hasBottomFrame &&
                  widget.model.canUseOpeningOnlyOptions) ...[
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    Localization.translate('سيستم او بي (System OB)', lang),
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  value: widget.model.useSystemOB,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) {
                    widget.model.toggleSystemOB(value);
                  },
                ),
                if (widget.model.canUseDemiOB)
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate('ديمي او بي (Demi OB)', lang),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: widget.model.effectiveUseDemiOB,
                    activeThumbColor: Colors.blue,
                    onChanged: (value) {
                      widget.model.toggleDemiOB(value);
                    },
                  ),
                if (widget.model.zones.any(
                  (z) => z.content == ZoneContent.doubleSash,
                ))
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      Localization.translate(
                        'فيرو سونترال (Verrou Central)',
                        lang,
                      ),
                      style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    value: widget.model.useVerrouCentral,
                    activeThumbColor: Colors.blue,
                    onChanged: (value) {
                      widget.model.toggleVerrouCentral(value);
                    },
                  ),
              ],

              if (ParcloseCutModeSelector.isAvailableFor(widget.model)) ...[
                const SizedBox(height: 8),
                ParcloseCutModeSelector(model: widget.model),
              ],

              if (!_pvcMontantReinforcementDisabled) ...[
                const Divider(height: 30),

                // 🟢 2. قسم تدعيم المونطو (يظهر دائماً في الأسفل)
                // 🟢 هذا الجزء يحل مشكلة تدعيم المونطو (Renfort)
                Text(
                  Localization.translate(
                    'تدعيم المونطو والأعمدة (Renfort)',
                    lang,
                  ),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                Builder(
                  builder: (context) {
                    final montantProfiles = <Map<String, dynamic>>[
                      ..._sashProfiles,
                      ..._slidingSashProfiles,
                      ...?(widget.model.effectiveSlidingSeries ??
                              widget.model.activeSlidingSeries)
                          ?.sections
                          .map((section) => section.toMap()),
                    ];
                    final bool isSupported = montantProfiles.any(
                      (item) =>
                          _isSlidingMontantCandidate(item, central: false) ||
                          _isSlidingMontantCandidate(item, central: true),
                    );

                    final bool hasThreePiece =
                        (widget
                                .model
                                .effectiveSlidingSeries
                                ?.hasThreePieceSash ??
                            widget
                                .model
                                .activeSlidingSeries
                                ?.hasThreePieceSash ??
                            false) ||
                        '${widget.model.effectiveSlidingSeries?.name ?? widget.model.activeSlidingSeries?.name ?? ''}'
                            .toLowerCase()
                            .contains('tpr');

                    // 2. إذا كانت السلسلة فيها مونطو منزلق (3 قطع) أو تم اختيار عمود مستقل ببراغي
                    if (hasThreePiece &&
                        (isSupported ||
                            widget.model.reinforcementMode ==
                                ReinforcementMode.independentScrewed) &&
                        firstSlidingZone != null) {
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            Localization.translate('الجانبي (Latéral):', lang),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            children: [
                              if (hasMeetingInCenter) ...[
                                buildCompactOption(
                                  Localization.translate('طرفية يسرى', lang),
                                  'lateral_0',
                                  firstSlidingZone,
                                ),
                                buildCompactOption(
                                  Localization.translate('طرفية يمنى', lang),
                                  'lateral_1',
                                  firstSlidingZone,
                                ),
                                buildCompactOption(
                                  Localization.translate('وسطى يسار', lang),
                                  'lateral_2',
                                  firstSlidingZone,
                                ),
                                buildCompactOption(
                                  Localization.translate('وسطى يمين', lang),
                                  'lateral_3',
                                  firstSlidingZone,
                                ),
                              ] else ...[
                                buildCompactOption(
                                  Localization.translate('يسرى', lang),
                                  'lateral_0',
                                  firstSlidingZone,
                                ),
                                buildCompactOption(
                                  Localization.translate('يمنى', lang),
                                  'lateral_1',
                                  firstSlidingZone,
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            Localization.translate('المركزي (Central):', lang),
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Builder(
                            builder: (context) {
                              final linkedCentral =
                                  widget
                                      .model
                                      .componentOverrides['قائم وسطي معزز (Sash Central Renforcé)']?['name'] ??
                                  widget
                                      .model
                                      .componentOverrides['قائم وسطي (Sash Central)']?['name'] ??
                                  widget.model
                                      .getSlidingSectionByType(
                                        'sash_central_reinforced',
                                      )
                                      ?.name ??
                                  widget.model
                                      .getSlidingSectionByType(
                                        'chicane_renforcee',
                                      )
                                      ?.name ??
                                  widget.model
                                      .getSlidingSectionByType('chicane')
                                      ?.name;
                              if (linkedCentral != null &&
                                  linkedCentral.toString().isNotEmpty) {
                                final rawProfile = linkedCentral.toString();
                                final localizedProfile =
                                    rawProfile.toLowerCase() ==
                                        'ouvrant central'
                                    ? switch (lang) {
                                        AppLanguage.arabic =>
                                          'القائم الوسطي للضلفة',
                                        AppLanguage.french => 'Ouvrant central',
                                        AppLanguage.english => 'Central sash',
                                      }
                                    : rawProfile;
                                return Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '${Localization.translate('البروفيل:', lang)} $localizedProfile',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: Colors.blue.shade700,
                                      fontStyle: FontStyle.italic,
                                    ),
                                  ),
                                );
                              }
                              return const SizedBox.shrink();
                            },
                          ),
                          Wrap(
                            children: List.generate(centralCount, (index) {
                              return SizedBox(
                                width: 120,
                                child: buildCompactOption(
                                  '${Localization.translate('مركز', lang)} ${index + 1}',
                                  centralKeys[index],
                                  firstSlidingZone,
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    }
                    // 3. إذا كانت السلسلة غير مدعومة
                    else if (firstSlidingZone != null) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          Localization.translate(
                            'هذه السلسلة لا تدعم تدعيم المونطو',
                            lang,
                          ),
                          style: const TextStyle(
                            color: Colors.red,
                            fontSize: 11,
                          ),
                        ),
                      );
                    }
                    // 4. إذا لم يكن هناك نظام منزلق أصلاً
                    else {
                      return const SizedBox.shrink();
                    }
                  },
                ),

                const Divider(height: 30),
                Text(
                  Localization.translate('مونتوسليم (Montant Slim)', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    color: Colors.blue,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 10),

                Builder(
                  builder: (context) {
                    final slimCandidates = widget.model
                        .getSlidingSlimCandidates();
                    if (slimCandidates.isNotEmpty && firstSlidingZone != null) {
                      final allSlimSelected = centralKeys.every(
                        (k) => firstSlidingZone.slidingMontantSlim[k] == true,
                      );
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                Localization.translate(
                                  'المركزي (Central):',
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              TextButton.icon(
                                style: TextButton.styleFrom(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  visualDensity: VisualDensity.compact,
                                ),
                                icon: Icon(
                                  allSlimSelected
                                      ? Icons.check_box
                                      : Icons.check_box_outline_blank,
                                  size: 16,
                                ),
                                label: Text(
                                  allSlimSelected
                                      ? Localization.translate(
                                          'إلغاء الكل',
                                          lang,
                                        )
                                      : Localization.translate(
                                          'تحديد الكل',
                                          lang,
                                        ),
                                  style: const TextStyle(fontSize: 11),
                                ),
                                onPressed: () {
                                  _setViewState(() {
                                    final newVal = !allSlimSelected;
                                    if (newVal) {
                                      for (final key in centralKeys) {
                                        firstSlidingZone
                                                .slidingMontantSlim[key] =
                                            true;
                                      }
                                    } else {
                                      // Cancel means no Slim member remains in
                                      // this sash, including obsolete keys from
                                      // an earlier leaf-count configuration.
                                      firstSlidingZone.slidingMontantSlim
                                          .clear();
                                    }
                                    if (newVal &&
                                        widget
                                                .model
                                                .selectedSlimMontantProfile ==
                                            null) {
                                      widget.model
                                          .applySlidingMontantSlimOverride(
                                            slimCandidates.first,
                                          );
                                    }
                                  });
                                  widget.model
                                      .clearSlidingMontantSlimOverrideIfInactive();
                                  widget.model.refreshUI();
                                },
                              ),
                            ],
                          ),
                          Wrap(
                            children: List.generate(centralCount, (index) {
                              return SizedBox(
                                width: 120,
                                child: buildCompactSlimOption(
                                  '${Localization.translate('مركز', lang)} ${index + 1}',
                                  centralKeys[index],
                                  firstSlidingZone,
                                ),
                              );
                            }),
                          ),
                        ],
                      );
                    } else if (firstSlidingZone != null) {
                      return Padding(
                        padding: const EdgeInsets.all(8.0),
                        child: Text(
                          Localization.translate(
                            'هذه السلسلة لا تدعم مونتوسليم',
                            lang,
                          ),
                          style: const TextStyle(
                            color: Colors.grey,
                            fontSize: 11,
                          ),
                        ),
                      );
                    } else {
                      return const SizedBox.shrink();
                    }
                  },
                ),
              ],
            ],
          );
        },
      ),
    );
  }

  List<Widget> _arrangeInTwoRows(List<Widget> rawItems) {
    // Keep the action palette compact. A long single line hides options behind
    // a horizontal scrollbar, whereas two deterministic rows keep both the
    // opening and sliding controls immediately visible.
    final items = rawItems.where((w) => w is! SizedBox).toList();
    if (items.isEmpty) return [];
    if (items.length <= 5) {
      return [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: items
              .map((item) => item is _Tier2RowItem ? item.child : item)
              .toList(growable: false),
        ),
      ];
    }

    final firstRow = <Widget>[];
    final secondRow = <Widget>[];
    final firstRowCapacity = (items.length + 1) ~/ 2;
    for (final item in items) {
      if (item is _Tier2RowItem) {
        // Explicit groups (opening / sliding frame choices) retain their
        // own stable row even when optional controls appear or disappear.
        (item.rowIndex == 0 ? firstRow : secondRow).add(item.child);
      } else if (firstRow.length < firstRowCapacity) {
        firstRow.add(item);
      } else {
        secondRow.add(item);
      }
    }
    return [
      Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: firstRow),
          const SizedBox(height: 8),
          Row(mainAxisSize: MainAxisSize.min, children: secondRow),
        ],
      ),
    ];
  }

  Widget _buildInteractiveBottomPanel(BuildContext context) {
    final hasSelection =
        widget.model.selectedZone != null ||
        widget.model.selection.type == SelectionType.frame ||
        widget.model.selection.type == SelectionType.mullion ||
        widget.model.zones.isNotEmpty;
    final isMullionSelected =
        widget.model.selection.type == SelectionType.mullion;

    // ── إذا تم تحديد الستار → اعرض لوحة الستار إذا كانت القائمة مرفوعة ──
    if (_isBottomPanelExpanded &&
        ((widget.model.isShutterOnly) ||
            (_isShutterSelected &&
                (widget.model.hasShutter ||
                    widget.model.drawNextShapeAsShutterOnly)))) {
      return _buildShutterBottomPanel(context);
    }

    final showExpanded = _isBottomPanelExpanded;

    // A collapsed contextual panel must leave no handle or reserved height.
    // Tapping a drawable frame/zone opens it again from the canvas hit-test.
    if (!showExpanded) {
      return const SizedBox.shrink();
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1A1A2E) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.white12 : Colors.grey.shade300,
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
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
              child: Row(
                children: [
                  IconButton(
                    tooltip: Localization.translate('إخفاء', lang),
                    visualDensity: VisualDensity.compact,
                    onPressed: () => _setViewState(() {
                      _isBottomPanelExpanded = false;
                    }),
                    icon: Icon(
                      Icons.keyboard_arrow_down_rounded,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.green.shade600,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _openMaterialConsumptionScreen(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.receipt_long_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 7),
                              Flexible(
                                child: Text(
                                  Localization.translate(
                                    'الكمية والتكلفة',
                                    lang,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Material(
                      color: Colors.blue.shade700,
                      borderRadius: BorderRadius.circular(8),
                      child: InkWell(
                        borderRadius: BorderRadius.circular(8),
                        onTap: () => _addDrawingAndCalculate(context),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(
                                Icons.add_shopping_cart_rounded,
                                size: 18,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  Localization.translate(
                                    'إضافة واحتساب السعر',
                                    lang,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            if (hasSelection) ...[
              // Tier 1: Horizontal Scrollable Tabs (شائع | إطار | ورقة | عامود | زجاج / حشوات)
              _buildTier1TabBar(isMullionSelected),
              const Divider(height: 1, thickness: 0.5),
              Container(
                height: 128,
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                child: _HorizontalWheelScrollArea(
                  builder: (context, controller) => SingleChildScrollView(
                    controller: controller,
                    scrollDirection: Axis.horizontal,
                    physics: const AlwaysScrollableScrollPhysics(),
                    child: Align(
                      alignment: AlignmentDirectional.topStart,
                      child: Row(
                        children: _arrangeInTwoRows(
                          _buildTier2Options(context, isMullionSelected),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ] else
              _buildZoneContentPaintPicker(context),
          ],
        ),
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════════
  // لوحة خصائص الستار السفلية
  // ═══════════════════════════════════════════════════════════════════
  /// Compact, deliberately manual content picker shown when no frame is
  /// selected. Choosing an item arms the paint tool; the next click on a
  /// frame applies the type instead of opening the panel automatically.
  Widget _buildZoneContentPaintPicker(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final canUseOpening = widget.systemMode != 'sliding';
    final canUseSliding =
        widget.systemMode == 'mixed' || widget.systemMode == 'sliding';

    Widget option(
      String label,
      IconData icon,
      ZoneContent content, {
      int? slidingSashesCount,
    }) {
      return Padding(
        padding: const EdgeInsetsDirectional.only(end: 8),
        child: _ContentButton(
          label: Localization.translate(label, lang),
          icon: icon,
          selected: false,
          onPressed: () {
            _startPaintbrushMode(
              zoneContent: content,
              slidingSashesCount: slidingSashesCount,
            );
            _setViewState(() {
              _isBottomPanelExpanded = false;
              _isShutterSelected = false;
            });
          },
        ),
      );
    }

    return Container(
      height: 100,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            Localization.translate('اختر النوع ثم اضغط على الإطار', lang),
            style: TextStyle(color: Colors.blue.shade700, fontSize: 12),
          ),
          const SizedBox(height: 6),
          Expanded(
            child: _HorizontalWheelScrollArea(
              builder: (context, controller) => SingleChildScrollView(
                controller: controller,
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    option('فارغة', Icons.crop_free_rounded, ZoneContent.empty),
                    if (canUseOpening)
                      option(
                        'زجاج ثابت',
                        Icons.window_rounded,
                        ZoneContent.fixedGlass,
                      ),
                    if (canUseOpening)
                      option(
                        'ضلفة واحدة',
                        Icons.door_back_door_rounded,
                        ZoneContent.singleSash,
                      ),
                    if (canUseOpening)
                      option(
                        'ضلفتان',
                        Icons.garage_rounded,
                        ZoneContent.doubleSash,
                      ),
                    if (canUseSliding)
                      option(
                        'منزلق 2',
                        Icons.sync_alt_rounded,
                        ZoneContent.slidingSash,
                        slidingSashesCount: 2,
                      ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTier1TabBar(bool isMullionSelected) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final List<Map<String, dynamic>> tabs = [
      {'id': 0, 'label': 'شائع', 'icon': Icons.tune_rounded},
      {'id': 1, 'label': 'إطار', 'icon': Icons.border_outer_rounded},
      {'id': 2, 'label': 'ورقة', 'icon': Icons.door_back_door_rounded},
      if (isMullionSelected)
        {'id': 3, 'label': 'عامود', 'icon': Icons.vertical_split_rounded},
      {'id': 4, 'label': 'زجاج / حشوات', 'icon': Icons.grid_on_rounded},
      {'id': 5, 'label': 'مقابض', 'icon': Icons.vpn_key_rounded},
      if (widget.model.hasShutter)
        {'id': 6, 'label': 'الستار', 'icon': Icons.layers_rounded},
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
            final isSelected = _isShutterSelected
                ? (id == 6)
                : (_activeBottomTab == id);

            return InkWell(
              onTap: () => _switchToBottomTab(id),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      color: isSelected ? Colors.blue : Colors.transparent,
                      width: 2.5,
                    ),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tab['icon'] as IconData,
                      size: 16,
                      color: isSelected
                          ? Colors.blue
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white54
                                : Colors.grey.shade600),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      Localization.translate(tab['label'] as String, lang),
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: isSelected
                            ? Colors.blue
                            : (Theme.of(context).brightness == Brightness.dark
                                  ? Colors.white60
                                  : Colors.grey.shade700),
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

  List<Widget> _buildTier2Options(
    BuildContext context,
    bool isMullionSelected,
  ) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final WindowZone? currentZone =
        widget.model.selectedZone ??
        (widget.model.zones.isNotEmpty ? widget.model.zones.first : null);
    if (currentZone == null && !isMullionSelected && _activeBottomTab != 1)
      return [];
    final WindowZone zone =
        currentZone ??
        (widget.model.zones.isNotEmpty
            ? widget.model.zones.first
            : WindowZone(
                id: '_fallback',
                boundary: Rect.fromLTWH(
                  0,
                  0,
                  widget.model.width,
                  widget.model.height,
                ),
                content: ZoneContent.empty,
              ));

    final supportedSlidingCounts = widget.model.supportedSlidingSashCounts;
    final supportedTrackCounts = widget.model.supportedSlidingTrackCounts;

    List<Widget> children = [];

    switch (_activeBottomTab) {
      case 0: // شائع (Common tools)
        if (widget.systemMode != 'sliding') {
          // 1. Split horizontal
          children.add(
            _ContentButton(
              label: Localization.translate('تقسيم أفقي', lang),
              icon: Icons.horizontal_split_rounded,
              selected: false,
              onPressed: () {
                _showSplitDialog(context, true);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          // 2. Split vertical
          children.add(
            _ContentButton(
              label: Localization.translate('تقسيم عمودي', lang),
              icon: Icons.vertical_split_rounded,
              selected: false,
              onPressed: () {
                _showSplitDialog(context, false);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        // 3. Reset Zoom
        if (!_isWindowsDesktop) {
          children.add(
            _ContentButton(
              label: Localization.translate('إعادة التكبير', lang),
              icon: Icons.zoom_out_map_rounded,
              selected: false,
              onPressed: _resetDrawingZoom,
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        // 4. Zone contents
        children.add(
          _ContentButton(
            label: Localization.translate('فارغة', lang),
            icon: Icons.crop_free_rounded,
            selected: zone.content == ZoneContent.empty,
            onPressed: () {
              widget.model.setSelectedZoneContent(ZoneContent.empty);
            },
          ),
        );
        children.add(const SizedBox(width: 8));

        if (widget.systemMode != 'sliding') {
          children.add(
            _ContentButton(
              label: Localization.translate('زجاج ثابت', lang),
              icon: Icons.window_rounded,
              selected: zone.content == ZoneContent.fixedGlass,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.fixedGlass);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        if (widget.systemMode != 'sliding' &&
            widget.model.canZoneHaveSash(zone)) {
          children.add(
            _ContentButton(
              label: Localization.translate('ضلفة واحدة', lang),
              icon: Icons.door_back_door_rounded,
              selected: zone.content == ZoneContent.singleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.singleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: Localization.translate('ضلفتان', lang),
              icon: Icons.garage_rounded,
              selected: zone.content == ZoneContent.doubleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.doubleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          if (widget.systemMode == 'mixed' && isSlidingSupported) {
            children.add(
              _ContentButton(
                label: Localization.translate('منزلق 2', lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 2,
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          Localization.translate(
                            _tr('نظام المنزلق لا يدعم الشكل المائل والمقوس'),
                            lang,
                          ),
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(2);
                  }
                },
              ),
            );

            if (supportedSlidingCounts.contains(3)) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 3', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                      zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 3,
                  onPressed: () async {
                    if (widget.model.hasArchOrSlant) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                              lang,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } else {
                      await _setSelectedZoneSlidingSashesFromUi(3);
                    }
                  },
                ),
              );
            }

            if (supportedSlidingCounts.contains(4)) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate('منزلق 4', lang),
                  icon: Icons.sync_alt_rounded,
                  selected:
                      zone.content == ZoneContent.slidingSash &&
                      zone.slidingSashesCount == 4,
                  onPressed: () async {
                    if (widget.model.hasArchOrSlant) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(
                            Localization.translate(
                              'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                              lang,
                            ),
                            textDirection: TextDirection.rtl,
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                    } else {
                      await _setSelectedZoneSlidingSashesFromUi(4);
                    }
                  },
                ),
              );
            }
          }
        } else if (isSlidingSupported) {
          children.add(
            _ContentButton(
              label: _slidingCountLabel(2, lang),
              icon: Icons.sync_alt_rounded,
              selected:
                  zone.content == ZoneContent.slidingSash &&
                  zone.slidingSashesCount == 2,
              onPressed: () async {
                if (widget.model.hasArchOrSlant) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                        textDirection: TextDirection.rtl,
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                } else {
                  await _setSelectedZoneSlidingSashesFromUi(2);
                }
              },
            ),
          );

          if (supportedSlidingCounts.contains(3)) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(3, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 3,
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(3);
                  }
                },
              ),
            );
          }

          if (supportedSlidingCounts.contains(4)) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(4, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == 4,
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(4);
                  }
                },
              ),
            );
          }
        }
        if (isSlidingSupported &&
            (widget.systemMode == 'sliding' || widget.systemMode == 'mixed')) {
          for (final count in const [5, 6]) {
            if (!supportedSlidingCounts.contains(count)) continue;
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _slidingCountLabel(count, lang),
                icon: Icons.sync_alt_rounded,
                selected:
                    zone.content == ZoneContent.slidingSash &&
                    zone.slidingSashesCount == count,
                onPressed: () async {
                  if (widget.model.hasArchOrSlant) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'نظام المنزلق لا يدعم الشكل المائل والمقوس',
                          textDirection: TextDirection.rtl,
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                  } else {
                    await _setSelectedZoneSlidingSashesFromUi(count);
                  }
                },
              ),
            );
          }
        }
        if (zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 16));
          children.add(
            Text(
              _trackShortTitle(lang),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          );
          for (final count in supportedTrackCounts.toList()..sort()) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: _trackCountLabel(count, lang),
                icon: Icons.view_week_rounded,
                selected: zone.slidingTrackCount == count,
                onPressed: () =>
                    widget.model.setSelectedZoneSlidingTracks(count),
              ),
            );
          }
          if (isSlidingFaceToFaceLayout(
            trackCount: zone.slidingTrackCount,
            sashCount: zone.slidingSashesCount,
          )) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: Localization.translate(
                  'التقاء الظرفتين الوسطيتين (Batmo central)',
                  lang,
                ),
                icon: Icons.layers_rounded,
                selected: zone.slidingFaceToFace,
                onPressed: () {
                  _setViewState(() {
                    widget.model.toggleSelectedZoneSlidingFaceToFace();
                  });
                },
              ),
            );
          }
          final supportsCacheRail =
              widget.model.getConfiguredSectionForRole(
                'cache_rail',
                useSlidingSeries: true,
              ) !=
              null;
          if (supportsCacheRail) {
            final cacheRailPerSide = math.max(0, zone.slidingTrackCount - 1);
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: widget.model.useOptionalCacheRail
                    ? 'كاش راي: $cacheRailPerSide يمين + $cacheRailPerSide يسار'
                    : 'كاش راي: غير مفعّل',
                icon: Icons.view_sidebar_rounded,
                selected: widget.model.useOptionalCacheRail,
                onPressed: () => widget.model.toggleCacheRail(
                  !widget.model.useOptionalCacheRail,
                ),
              ),
            );
          }
        }
        if (!widget.model.isPVC &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.hasSashPlintheBottom
                  ? 'حذف بلانت الضلفة'
                  : 'إضافة بلانت للضلفة',
              icon: Icons.border_bottom_rounded,
              selected: zone.hasSashPlintheBottom,
              onPressed: () {
                _setViewState(() {
                  widget.model.toggleSelectedZoneSashPlintheBottom();
                });
              },
            ),
          );
        }
        break;

      case 1: // إطار (Frame settings)
        final bool selectedZoneUsesSlidingFrame =
            zone.content == ZoneContent.slidingSash ||
            (widget.systemMode == 'sliding' &&
                zone.content != ZoneContent.empty &&
                zone.content != ZoneContent.fixedGlass);
        final bool selectedZoneUsesOpeningFrame =
            !selectedZoneUsesSlidingFrame &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash ||
                zone.content == ZoneContent.fixedGlass ||
                zone.content == ZoneContent.empty);

        bool isFrameCompatibleWithCurrentDrawing(
          Map<String, dynamic> item, {
          required bool sliding,
        }) {
          bool readBool(Object? value, {required bool fallback}) {
            if (value is bool) return value;
            if (value is num) return value != 0;
            final normalized = value?.toString().trim().toLowerCase();
            if (normalized == '1' ||
                normalized == 'true' ||
                normalized == 'yes') {
              return true;
            }
            if (normalized == '0' ||
                normalized == 'false' ||
                normalized == 'no') {
              return false;
            }
            return fallback;
          }

          final integratedCover = readBool(
            item['design_integrated_side_cover'] ??
                item['integrated_side_cover'],
            fallback: profileHasIntegratedSideCover(item),
          );
          final allowedWithShutter = readBool(
            item['design_allowed_with_shutter'] ?? item['allowed_with_shutter'],
            fallback: true,
          );

          // 1. Shutter compatibility:
          if (widget.model.hasShutter) {
            if (!allowedWithShutter) return false;
          }

          // 2. Side covers compatibility:
          if (widget.model.hasSideCovers) {
            final hasIntegratedCover =
                widget.model.integratedFrameSideCoverWidth > 0;
            final hasSeparateCover = !hasIntegratedCover;
            if (hasSeparateCover) {
              if (integratedCover) return false;
            }
            // Plain frames are always valid here: when the cover is enabled,
            // selecting one keeps the switch and uses a separate cover.
          }

          // 3. 90° Profile angle compatibility:
          if (widget.model.usesProfileAngle && integratedCover) {
            try {
              final compatible = widget.model.findCompatibleNoCoverFrame(
                currentFrame: AluminumSection.fromMap(item),
                sliding: sliding,
              );
              if (compatible == null) return false;
            } catch (_) {
              return false;
            }
          }

          return true;
        }

        final angleJunctionFrames = widget.model
            .getProfileAngleJunctionFrames();
        final angleJunctionFrameIds = angleJunctionFrames.values
            .map((e) => e.section.id)
            .toSet();
        final personalizedFrameProfiles =
            <({Map<String, dynamic> profile, bool sliding})>[];
        final personalizedFrameIds = <int>{};
        for (final frame in widget.model.getFrameRects()) {
          final sliding = widget.model.frameUsesSlidingSeries(frame);
          for (final side in const ['top', 'right', 'bottom', 'left']) {
            final override = widget.model.frameSideOverrideForRect(frame, side);
            if (override == null) continue;
            final id = _catalogRowId(override);
            if (id == null || !personalizedFrameIds.add(id)) continue;
            personalizedFrameProfiles.add((
              profile: override,
              sliding: sliding,
            ));
          }
        }

        List<Map<String, dynamic>> profilesForPickerMode(
          List<Map<String, dynamic>> profiles, {
          required bool sliding,
        }) {
          if (_showAllFrameProfiles) return profiles.toList();

          final currentMap = sliding
              ? (widget.model.slidingFrameOverride ??
                    widget.model.getSlidingBaseFrameSection()?.toMap())
              : (widget.model.frameOverride ??
                    widget.model.getSectionByType('frame')?.toMap());
          final currentId = currentMap == null
              ? null
              : _catalogRowId(currentMap);

          return profiles.where((profile) {
            final id = _catalogRowId(profile);
            if (id != null && id == currentId) return true;
            if (id != null && angleJunctionFrameIds.contains(id)) return true;
            if (id != null && personalizedFrameIds.contains(id)) return true;
            return isFrameCompatibleWithCurrentDrawing(
              profile,
              sliding: sliding,
            );
          }).toList();
        }

        final rawOpeningProfiles = (widget.systemMode == 'sliding')
            ? <Map<String, dynamic>>[]
            : (widget.systemMode == 'mixed'
                  ? (_openingFrameProfiles.isNotEmpty
                        ? _openingFrameProfiles
                        : _frameProfiles)
                  : (_openingFrameProfiles.isNotEmpty
                        ? _openingFrameProfiles
                        : _frameProfiles));
        final openingProfiles = profilesForPickerMode(
          rawOpeningProfiles,
          sliding: false,
        );
        // `mixed` describes the editor route, not necessarily the current
        // drawing. A Project Baton door must not display sliding frames just
        // because the route supports both families.
        final drawingHasSlidingFrame = widget.model.zones.any(
          (candidate) => candidate.content == ZoneContent.slidingSash,
        );
        final rawSlidingProfiles =
            (drawingHasSlidingFrame || selectedZoneUsesSlidingFrame)
            ? _slidingFrameProfiles
            : <Map<String, dynamic>>[];
        final slidingProfiles =
            profilesForPickerMode(rawSlidingProfiles, sliding: true)
                // The one-track profile is an automatic extension selected from
                // the series rules; it is not a replacement for the two-track
                // base frame and therefore must not be shown in this picker.
                .where(
                  (profile) => !widget.model.isSlidingFrameExtension(profile),
                )
                .toList();

        for (final entry in angleJunctionFrames.values) {
          final targetList = entry.sliding ? slidingProfiles : openingProfiles;
          final secMap = entry.section.toMap();
          final id = _catalogRowId(secMap);
          if (id != null && !targetList.any((p) => _catalogRowId(p) == id)) {
            targetList.insert(0, secMap);
          }
        }
        for (final entry in personalizedFrameProfiles) {
          final targetList = entry.sliding ? slidingProfiles : openingProfiles;
          final id = _catalogRowId(entry.profile);
          if (id != null && !targetList.any((p) => _catalogRowId(p) == id)) {
            targetList.insert(0, entry.profile);
          }
        }

        Future<void> selectFrameProfile(
          Map<String, dynamic> item, {
          required bool sliding,
        }) async {
          final selectedMap = sliding
              ? widget.model.slidingFrameOverride
              : widget.model.frameOverride;
          if (selectedMap?['id'] == item['id']) return;

          bool readBool(Object? value, {required bool fallback}) {
            if (value is bool) return value;
            if (value is num) return value != 0;
            final normalized = value?.toString().trim().toLowerCase();
            if (normalized == '1' ||
                normalized == 'true' ||
                normalized == 'yes') {
              return true;
            }
            if (normalized == '0' ||
                normalized == 'false' ||
                normalized == 'no') {
              return false;
            }
            return fallback;
          }

          final integratedCover = readBool(
            item['design_integrated_side_cover'] ??
                item['integrated_side_cover'],
            fallback: profileHasIntegratedSideCover(item),
          );
          final allowsStandaloneCover = readBool(
            item['design_allows_side_cover'] ?? item['allows_side_cover'],
            fallback: true,
          );
          final allowedWithShutter = readBool(
            item['design_allowed_with_shutter'] ?? item['allowed_with_shutter'],
            fallback: true,
          );
          final removesSideCover =
              widget.model.hasSideCovers &&
              !integratedCover &&
              !allowsStandaloneCover;
          final removesShutter = widget.model.hasShutter && !allowedWithShutter;

          var removesProfileAngle = false;
          if (widget.model.usesProfileAngle && integratedCover) {
            try {
              removesProfileAngle =
                  widget.model.findCompatibleNoCoverFrame(
                    currentFrame: AluminumSection.fromMap(item),
                    sliding: sliding,
                  ) ==
                  null;
            } catch (_) {
              removesProfileAngle = true;
            }
          }

          final impacts = <String>[
            if (removesSideCover)
              Localization.translate('سيتم إلغاء الغطاء الجانبي', lang),
            if (removesShutter)
              Localization.translate('سيتم إلغاء الستار', lang),
            if (removesProfileAngle)
              Localization.translate('سيتم إلغاء بروفيل الزاوية', lang),
          ];
          if (impacts.isNotEmpty) {
            final confirmed = await showDialog<bool>(
              context: context,
              builder: (dialogContext) => AlertDialog(
                title: Text(Localization.translate('تأكيد تغيير الإطار', lang)),
                content: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      Localization.translate(
                        'هذا الإطار غير متوافق مع بعض تجهيزات الرسم. إذا تابعت:',
                        lang,
                      ),
                    ),
                    const SizedBox(height: 12),
                    for (final impact in impacts)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 6),
                        child: Text('• $impact'),
                      ),
                  ],
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(dialogContext, false),
                    child: Text(Localization.translate('إلغاء', lang)),
                  ),
                  FilledButton(
                    onPressed: () => Navigator.pop(dialogContext, true),
                    child: Text(Localization.translate('متابعة', lang)),
                  ),
                ],
              ),
            );
            if (confirmed != true || !mounted) return;
          }

          final mutableSelected = Map<String, dynamic>.from(item);
          mutableSelected['calculated_price'] =
              await _sectionPriceForSelectedColor(mutableSelected);
          if (!mounted) return;
          if (removesShutter) widget.model.toggleShutter(false);
          if (removesProfileAngle) widget.model.clearProfileAngle();
          _setViewState(() {
            widget.model.applyFrameOverride(
              mutableSelected,
              sliding: sliding,
              manualSelection: true,
            );
            if (widget.model.usesProfileAngle) {
              widget.model.adaptFramesForProfileAngle();
            }
            widget.model.updateProfileThickness();
            widget.model.refreshUI();
          });
          await widget.model.syncFrameReinforcement();
          if (mounted) _setViewState(() {});
        }

        final Map<String, dynamic>? activeOpeningFrameMap =
            widget.model.getFrameRects().length > 1 &&
                (widget.model.frameOverride == null ||
                    !openingProfiles.any(
                      (p) => p['id'] == widget.model.frameOverride?['id'],
                    )) &&
                openingProfiles.isNotEmpty
            ? openingProfiles.first
            : widget.model.frameOverride;

        final Map<String, dynamic>? activeSlidingFrameMap =
            widget.model.getFrameRects().length > 1 &&
                (widget.model.slidingFrameOverride == null ||
                    !slidingProfiles.any(
                      (p) =>
                          p['id'] == widget.model.slidingFrameOverride?['id'],
                    )) &&
                slidingProfiles.isNotEmpty
            ? slidingProfiles.first
            : widget.model.getSlidingBaseFrameSection()?.toMap();

        final hasBothFrameFamilies =
            openingProfiles.isNotEmpty && slidingProfiles.isNotEmpty;

        void addFrameProfileButtons(
          List<Map<String, dynamic>> profiles, {
          required bool sliding,
          required String prefix,
        }) {
          for (var item in profiles) {
            final codeStr =
                (item['code'] != null && item['code'].toString().isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = prefix.isEmpty
                ? '$codeStr$nameStr'
                : '$prefix: $codeStr$nameStr';
            final selectedMap = sliding
                ? activeSlidingFrameMap
                : activeOpeningFrameMap;
            final isSelected =
                selectedMap != null && selectedMap['id'] == item['id'];

            final button = Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ProfileButton(
                label: label,
                code: item['code']?.toString(),
                imagePath: item['image_path']?.toString(),
                selected: isSelected,
                onPressed: () => selectFrameProfile(item, sliding: sliding),
              ),
            );
            children.add(
              hasBothFrameFamilies
                  ? _Tier2RowItem(rowIndex: sliding ? 1 : 0, child: button)
                  : button,
            );
          }
        }

        if (openingProfiles.isEmpty && slidingProfiles.isEmpty) {
          children.add(
            Text(
              Localization.translate(
                'لا توجد إطارات متوفرة لهذه السلسلة',
                lang,
              ),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else {
          if (angleJunctionFrames.isNotEmpty) {
            for (final entry in angleJunctionFrames.values) {
              final isSliding = entry.sliding;
              final sec = entry.section;
              final codeStr = (sec.code != null && sec.code!.isNotEmpty)
                  ? '${sec.code} - '
                  : '';
              final typeLabel = isSliding
                  ? Localization.translate('منزلق', lang)
                  : Localization.translate('فتح', lang);
              final label =
                  '${Localization.translate('إطار زاوية 90°', lang)} ($typeLabel): $codeStr${sec.name}';
              final btn = Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: sec.code,
                  imagePath: sec.imagePath,
                  selected: true,
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          '${Localization.translate('إطار زاوية 90° معتمد في جدول الكمية والتكلفة', lang)}: $codeStr${sec.name}',
                        ),
                        duration: const Duration(seconds: 2),
                      ),
                    );
                  },
                ),
              );
              children.add(
                hasBothFrameFamilies
                    ? _Tier2RowItem(rowIndex: isSliding ? 1 : 0, child: btn)
                    : btn,
              );
            }
            children.add(const SizedBox(width: 8));
          }
          if (openingProfiles.isNotEmpty) {
            addFrameProfileButtons(openingProfiles, sliding: false, prefix: '');
          }
          if (slidingProfiles.isNotEmpty) {
            if (openingProfiles.isNotEmpty) {
              children.add(const SizedBox(width: 8));
            }
            addFrameProfileButtons(slidingProfiles, sliding: true, prefix: '');
          }
        }

        final selectedPhysicalFrame = widget.model.frameRectForSelection(
          widget.model.selection.zoneId,
        );
        if (selectedPhysicalFrame != null) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: Localization.translate('تخصيص جهات الإطار', lang),
              icon: Icons.open_with_rounded,
              selected: widget.model.frameHasSideOverrides(
                selectedPhysicalFrame,
              ),
              onPressed: () => _showFrameSideProfileDialog(context),
            ),
          );
        }

        // زر الغطاء الجانبي (Side Cover toggle)
        children.add(const SizedBox(width: 8));
        final bool isNestedSlidingFrame =
            zone != null && widget.model.isSlidingZoneNestedInSingleFrame(zone);
        if (isNestedSlidingFrame) {
          children.add(
            _ContentButton(
              label: widget.model.hasInternalSlidingSideCover
                  ? Localization.translate('إزالة غطاء الإطار المنزلق', lang)
                  : Localization.translate('إضافة غطاء الإطار المنزلق', lang),
              icon: widget.model.hasInternalSlidingSideCover
                  ? Icons.border_clear_rounded
                  : Icons.border_outer_rounded,
              selected: widget.model.hasInternalSlidingSideCover,
              onPressed: () {
                widget.model.toggleInternalSlidingSideCover(
                  !widget.model.hasInternalSlidingSideCover,
                );
                _setViewState(() {});
              },
            ),
          );
        } else {
          children.add(
            _ContentButton(
              label: widget.model.hasSideCovers
                  ? Localization.translate('إزالة غطاء جانبي', lang)
                  : Localization.translate('إضافة غطاء جانبي', lang),
              icon: widget.model.hasSideCovers
                  ? Icons.border_clear_rounded
                  : Icons.border_outer_rounded,
              selected: widget.model.hasSideCovers,
              showWarning: false,
              onPressed: () async {
                await widget.model.toggleSideCovers(
                  !widget.model.hasSideCovers,
                );
                _setViewState(() {});
              },
            ),
          );
        }

        // بروفيل الزاوية وصلة بين إطارين مستقلين، فلا يظهر لإطار واحد.
        if (widget.model.getFrameRects().length >= 2) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: widget.model.usesProfileAngle
                  ? '${Localization.translate('بروفيل زاوية 90°', lang)}: ${widget.model.localizedProfileAngleModeName(lang)}'
                  : Localization.translate('إضافة بروفيل زاوية 90°', lang),
              icon: Icons.square_foot_rounded,
              selected: widget.model.usesProfileAngle,
              onPressed: () => _showProfileAngleDialog(context),
            ),
          );
        }

        if (!widget.model.isPVC &&
            widget.model.hasPlintheSupport &&
            (selectedZoneUsesOpeningFrame ||
                widget.model.canUseOpeningOnlyOptions)) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: widget.model.hasFramePlintheBottom
                  ? Localization.translate('حذف بلانت الإطار', lang)
                  : Localization.translate('إضافة بلانت للإطار', lang),
              icon: Icons.border_bottom_rounded,
              selected: widget.model.hasFramePlintheBottom,
              onPressed: () {
                widget.model.toggleFramePlintheBottom(
                  !widget.model.hasFramePlintheBottom,
                );
                _setViewState(() {});
              },
            ),
          );
        }

        final selectedFrameUsesSlidingSeries = selectedZoneUsesSlidingFrame;
        final selectedSeriesHasC =
            widget.model.getConfiguredSectionForRole(
              'seuil',
              useSlidingSeries: selectedFrameUsesSlidingSeries,
            ) !=
            null;
        if (selectedSeriesHasC) {
          final cIsRequired = widget.model.isConfiguredRoleRequired(
            'seuil',
            useSlidingSeries: selectedFrameUsesSlidingSeries,
          );
          final cIsEnabled = widget.model.usesFrameRole(
            'seuil',
            sliding: selectedFrameUsesSlidingSeries,
          );
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: 'Seuil',
              icon: Icons.horizontal_rule_rounded,
              selected: cIsEnabled,
              onPressed: () {
                if (cIsRequired) return;
                widget.model.toggleSeuil(!cIsEnabled);
                _setViewState(() {});
              },
            ),
          );
        }
        break;

      case 2: // ورقة (Sash settings)
        final bool isSliding =
            widget.systemMode == 'sliding' ||
            (widget.systemMode == 'mixed' &&
                zone.content == ZoneContent.slidingSash);
        final expectedSashSeriesId = isSliding
            ? (widget.model.effectiveSlidingSeries?.id ??
                  widget.model.activeSlidingSeries?.id)
            : widget.model.activeSeries?.id;
        final sashProfiles = isSliding
            ? (_slidingSashProfiles.isNotEmpty
                  ? _slidingSashProfiles
                  : (_loadedSeriesId == expectedSashSeriesId
                        ? _sashProfiles
                        : const <Map<String, dynamic>>[]))
            : (_openingSashProfiles.isNotEmpty
                  ? _openingSashProfiles
                  : (_loadedSeriesId == expectedSashSeriesId
                        ? _sashProfiles
                        : const <Map<String, dynamic>>[]));
        if (!isSliding) {
          children.add(
            _ContentButton(
              label: Localization.translate('ضلفة واحدة', lang),
              icon: Icons.door_back_door_rounded,
              selected: zone.content == ZoneContent.singleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.singleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: Localization.translate('ضلفتان', lang),
              icon: Icons.garage_rounded,
              selected: zone.content == ZoneContent.doubleSash,
              onPressed: () {
                widget.model.setSelectedZoneContent(ZoneContent.doubleSash);
              },
            ),
          );
          children.add(const SizedBox(width: 8));
        }

        if (sashProfiles.isEmpty) {
          children.add(
            Text(
              Localization.translate('لا توجد درف متوفرة لهذه السلسلة', lang),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else if (isSliding) {
          List<Map<String, dynamic>> uniqueProfiles(
            Iterable<Map<String, dynamic>> profiles,
          ) {
            final seen = <String>{};
            return profiles.where((profile) {
              final key =
                  _catalogRowId(profile)?.toString() ??
                  '${profile['code'] ?? ''}|${profile['name'] ?? ''}';
              return seen.add(key);
            }).toList();
          }

          final lateralProfiles = uniqueProfiles(
            sashProfiles.where(
              (s) =>
                  _isSlidingMontantCandidate(s, central: false) &&
                  (!_pvcMontantReinforcementDisabled ||
                      !_isReinforcedMontant(s, central: false)),
            ),
          );

          final centralProfiles = uniqueProfiles(
            sashProfiles.where(
              (s) =>
                  _isSlidingMontantCandidate(s, central: true) &&
                  (!_pvcMontantReinforcementDisabled ||
                      !_isReinforcedMontant(s, central: true)),
            ),
          );
          final traverseProfiles = uniqueProfiles(
            sashProfiles.where((profile) {
              final type = '${profile['type'] ?? ''}'.toLowerCase();
              final name = '${profile['name'] ?? ''}'.toLowerCase();
              return type.contains('sash_traverse') ||
                  type.contains('traverse') ||
                  name.contains('traverse') ||
                  name.contains('ترافيرس');
            }),
          );
          final baseSashProfiles = uniqueProfiles(
            sashProfiles.where((profile) {
              final role = '${profile['design_role_key'] ?? ''}'
                  .trim()
                  .toLowerCase();
              final isMontant =
                  _isSlidingMontantCandidate(profile, central: false) ||
                  _isSlidingMontantCandidate(profile, central: true);
              final isTraverse = traverseProfiles.any(
                (candidate) =>
                    _catalogRowId(candidate) == _catalogRowId(profile),
              );
              final isSlim = widget.model.isSlidingMontantSlimCandidate(
                profile,
              );
              return !isMontant &&
                  !isTraverse &&
                  !isSlim &&
                  (role.isEmpty ||
                      role == 'sash' ||
                      role == 'sash_extension' ||
                      role == 'sliding_sash');
            }),
          );
          final slimProfiles = uniqueProfiles(
            widget.model.getSlidingSlimCandidates(),
          );

          if (baseSashProfiles.isNotEmpty) {
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('الضلفة (Ouvrant):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            for (final item in baseSashProfiles) {
              final activeSlidingSash =
                  widget.model.selectedZone?.slidingSashOverride ??
                  widget.model.slidingSashOverride;
              final selected =
                  activeSlidingSash?['id']?.toString() ==
                  item['id']?.toString();
              final code = '${item['code'] ?? ''}'.trim();
              final name = '${item['name'] ?? 'بدون اسم'}'.trim();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: code.isEmpty ? name : '$code - $name',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      if (!mounted) return;
                      _setViewState(() {
                        widget.model.applySashOverride(
                          chosen,
                          sliding: true,
                          manualSelection: true,
                          targetZone: widget.model.selectedZone,
                        );
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
            children.add(const SizedBox(width: 12));
          }

          bool isLateralSelected(Map<String, dynamic> item) {
            final bool itemIsReinforced = widget.model
                .isSlidingMontantReinforced(item, central: false);

            final bool hasAnyReinforced =
                !_pvcMontantReinforcementDisabled &&
                widget.model.zones.any(
                  (z) =>
                      z.content == ZoneContent.slidingSash &&
                      z.slidingMontantReinforced.entries.any(
                        (e) => e.key.startsWith('lateral_') && e.value == true,
                      ),
                );

            final bool hasAnyNormal = widget.model.zones.any((z) {
              if (z.content != ZoneContent.slidingSash) return false;
              final sashes = z.slidingSashesCount > 0
                  ? z.slidingSashesCount
                  : 2;
              final bool hasMeetingInCenter =
                  z.slidingFaceToFace &&
                  isSlidingFaceToFaceLayout(
                    trackCount: z.slidingTrackCount,
                    sashCount: sashes,
                  );
              final lateralCount = hasMeetingInCenter ? 4 : 2;
              for (var i = 0; i < lateralCount; i++) {
                if (z.slidingMontantReinforced['lateral_$i'] != true) {
                  return true;
                }
              }
              return false;
            });

            if (itemIsReinforced && !hasAnyReinforced) {
              return false;
            }
            if (!itemIsReinforced && !hasAnyNormal) {
              return false;
            }

            final current =
                widget.model.componentOverrides[itemIsReinforced
                    ? 'قائم جانبي معزز (Sash Lateral Renforcé)'
                    : 'قائم جانبي (Sash Lateral)'] ??
                (!itemIsReinforced
                    ? widget.model.componentOverrides['قائم جانبي (Lateral)']
                    : null);
            if (current is Map &&
                current['id']?.toString() == '${item['id']}') {
              return true;
            }
            if (current != null) return false;

            final firstMatching = lateralProfiles.firstWhere(
              (p) =>
                  widget.model.isSlidingMontantReinforced(p, central: false) ==
                  itemIsReinforced,
              orElse: () => lateralProfiles.first,
            );
            return '${firstMatching['id']}' == '${item['id']}';
          }

          bool isCentralSelected(Map<String, dynamic> item) {
            // A slim central member visually replaces the chicane at that
            // junction. Keep the catalogue selection intact for geometry,
            // but do not leave a Chicane button highlighted beside Slim.
            final role = '${item['design_role_key'] ?? ''}'
                .trim()
                .toLowerCase();
            final itemText = '${item['name'] ?? ''} ${item['type'] ?? ''}'
                .toLowerCase();
            final isChicane =
                role == 'chicane' ||
                itemText.contains('chicane') ||
                itemText.contains('شيكان');
            final hasSlimCentral = widget.model.hasActiveSlidingMontantSlim;
            if (isChicane && hasSlimCentral) return false;

            final bool itemIsReinforced = widget.model
                .isSlidingMontantReinforced(item, central: true);

            final bool hasAnyReinforced =
                !_pvcMontantReinforcementDisabled &&
                widget.model.zones.any(
                  (z) =>
                      z.content == ZoneContent.slidingSash &&
                      z.slidingMontantReinforced.entries.any(
                        (e) => e.key.startsWith('central_') && e.value == true,
                      ),
                );

            final bool hasAnyNormal = widget.model.zones.any((z) {
              if (z.content != ZoneContent.slidingSash) return false;
              final sashes = z.slidingSashesCount > 0
                  ? z.slidingSashesCount
                  : 2;
              final bool hasMeetingInCenter =
                  z.slidingFaceToFace &&
                  isSlidingFaceToFaceLayout(
                    trackCount: z.slidingTrackCount,
                    sashCount: sashes,
                  );
              final centralCount = hasMeetingInCenter
                  ? (sashes == 4 ? 4 : 8)
                  : math.max(0, (sashes * 2) - 2);
              for (var i = 0; i < centralCount; i++) {
                if (z.slidingMontantReinforced['central_$i'] != true) {
                  return true;
                }
              }
              return false;
            });

            if (itemIsReinforced && !hasAnyReinforced) {
              return false;
            }
            if (!itemIsReinforced && !hasAnyNormal) {
              return false;
            }

            final current =
                widget.model.componentOverrides[itemIsReinforced
                    ? 'قائم وسطي معزز (Sash Central Renforcé)'
                    : 'قائم وسطي (Sash Central)'] ??
                (!itemIsReinforced
                    ? (widget.model.componentOverrides['قائم وسطي (Central)'] ??
                          widget.model.componentOverrides['الشيكان (Chicane)'])
                    : null);
            if (current is Map &&
                current['id']?.toString() == '${item['id']}') {
              return true;
            }
            if (current != null) return false;

            final firstMatching = centralProfiles.firstWhere(
              (p) =>
                  widget.model.isSlidingMontantReinforced(p, central: true) ==
                  itemIsReinforced,
              orElse: () => centralProfiles.first,
            );
            return '${firstMatching['id']}' == '${item['id']}';
          }

          void selectLateral(Map<String, dynamic> item) async {
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] =
                await _sectionPriceForSelectedColor(mutableSelected);

            if (traverseProfiles.isNotEmpty &&
                widget.model.componentOverrides['سكة الظلفة (Sash Traverse)'] ==
                    null) {
              final chosenTraverse = Map<String, dynamic>.from(
                traverseProfiles.first,
              );
              chosenTraverse['calculated_price'] =
                  await _sectionPriceForSelectedColor(chosenTraverse);
              widget.model.componentOverrides['سكة الظلفة (Sash Traverse)'] =
                  chosenTraverse;
            }

            _setViewState(() {
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: false,
                manualSelection: true,
                updateAllMembers: true,
              );
              widget.model.refreshUI();
            });
          }

          void selectCentral(Map<String, dynamic> item) async {
            final mutableSelected = Map<String, dynamic>.from(item);
            mutableSelected['calculated_price'] =
                await _sectionPriceForSelectedColor(mutableSelected);
            final role = '${item['design_role_key'] ?? ''}'
                .trim()
                .toLowerCase();
            final itemText = '${item['name'] ?? ''} ${item['type'] ?? ''}'
                .toLowerCase();
            final isChicane =
                role == 'chicane' ||
                itemText.contains('chicane') ||
                itemText.contains('شيكان');

            if (traverseProfiles.isNotEmpty &&
                widget.model.componentOverrides['سكة الظلفة (Sash Traverse)'] ==
                    null) {
              final chosenTraverse = Map<String, dynamic>.from(
                traverseProfiles.first,
              );
              chosenTraverse['calculated_price'] =
                  await _sectionPriceForSelectedColor(chosenTraverse);
              widget.model.componentOverrides['سكة الظلفة (Sash Traverse)'] =
                  chosenTraverse;
            }

            _setViewState(() {
              // Chicane and montant central slim are mutually exclusive.
              // Clearing only the per-zone choice restores the normal/chicane
              // sash drawing while keeping the catalog selection available for
              // a later explicit Slim selection.
              if (isChicane) {
                for (final zone in widget.model.zones) {
                  if (zone.content != ZoneContent.slidingSash) continue;
                  for (final key in zone.slidingMontantSlim.keys.toList()) {
                    zone.slidingMontantSlim[key] = false;
                  }
                }
              }
              widget.model.applySlidingMontantOverride(
                mutableSelected,
                central: true,
                manualSelection: true,
                updateAllMembers: true,
              );
              widget.model.refreshUI();
            });
          }

          final bool hasThreePieceSliding =
              (widget.model.effectiveSlidingSeries?.hasThreePieceSash ??
                  widget.model.activeSlidingSeries?.hasThreePieceSash ??
                  false) ||
              '${widget.model.effectiveSlidingSeries?.name ?? widget.model.activeSlidingSeries?.name ?? ''}'
                  .toLowerCase()
                  .contains('tpr');

          if (hasThreePieceSliding && lateralProfiles.isNotEmpty) {
            // Add Lateral label
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('الجانبي (Lateral):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );

            for (var item in lateralProfiles) {
              final codeStr =
                  (item['code'] != null && item['code'].toString().isNotEmpty)
                  ? '${item['code']} - '
                  : '';
              final nameStr = item['name'] ?? 'بدون اسم';
              final label = '$codeStr$nameStr';
              final isSelected = isLateralSelected(item);

              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: label,
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: isSelected,
                    onPressed: () => selectLateral(item),
                  ),
                ),
              );
            }

            children.add(const SizedBox(width: 12));
          }

          if (hasThreePieceSliding && centralProfiles.isNotEmpty) {
            // Add Central label
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('الوسطي (Central):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );

            for (var item in centralProfiles) {
              final codeStr =
                  (item['code'] != null && item['code'].toString().isNotEmpty)
                  ? '${item['code']} - '
                  : '';
              final nameStr = item['name'] ?? 'بدون اسم';
              final label = '$codeStr$nameStr';
              final isSelected = isCentralSelected(item);

              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: label,
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: isSelected,
                    onPressed: () => selectCentral(item),
                  ),
                ),
              );
            }
          }
          if (traverseProfiles.isNotEmpty) {
            children.add(const SizedBox(width: 12));
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('سكة الظلفة (Sash Traverse)', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            for (final item in traverseProfiles) {
              final selected =
                  widget
                      .model
                      .componentOverrides['سكة الظلفة (Sash Traverse)']?['id']
                      ?.toString() ==
                  item['id']?.toString();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: '${item['code'] ?? ''} - ${item['name'] ?? ''}',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      _setViewState(() {
                        widget
                                .model
                                .componentOverrides['سكة الظلفة (Sash Traverse)'] =
                            chosen;
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
          }
          if (slimProfiles.isNotEmpty) {
            children.add(const SizedBox(width: 12));
            children.add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                child: Text(
                  Localization.translate('المونتوسليم (Montant Slim):', lang),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: Colors.blue,
                  ),
                ),
              ),
            );
            final activeSlimProfile = widget.model.selectedSlimMontantProfile;
            for (final item in slimProfiles) {
              final selected =
                  activeSlimProfile != null &&
                  activeSlimProfile['id']?.toString() == item['id']?.toString();
              children.add(
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _ProfileButton(
                    label: '${item['code'] ?? ''} - ${item['name'] ?? ''}',
                    code: item['code']?.toString(),
                    imagePath: item['image_path']?.toString(),
                    selected: selected,
                    onPressed: () async {
                      final chosen = Map<String, dynamic>.from(item);
                      chosen['calculated_price'] =
                          await _sectionPriceForSelectedColor(chosen);
                      _setViewState(() {
                        widget.model.applySlidingMontantSlimOverride(chosen);
                        widget.model.refreshUI();
                      });
                    },
                  ),
                ),
              );
            }
          }
        } else {
          for (var item in sashProfiles) {
            final codeStr =
                (item['code'] != null && item['code'].toString().isNotEmpty)
                ? '${item['code']} - '
                : '';
            final nameStr = item['name'] ?? 'بدون اسم';
            final label = '$codeStr$nameStr';
            final currentSashOverride =
                zone.sashOverride ?? widget.model.sashOverride;
            final isSelected =
                currentSashOverride != null &&
                currentSashOverride['id'] == item['id'];

            children.add(
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ProfileButton(
                  label: label,
                  code: item['code']?.toString(),
                  imagePath: item['image_path']?.toString(),
                  selected: isSelected,
                  onPressed: () async {
                    final mutableSelected = Map<String, dynamic>.from(item);
                    mutableSelected['calculated_price'] =
                        await _sectionPriceForSelectedColor(mutableSelected);
                    _setViewState(() {
                      widget.model.applySashOverride(
                        mutableSelected,
                        sliding: false,
                        manualSelection: true,
                        targetZone: zone,
                      );
                      widget.model.refreshUI();
                    });
                  },
                ),
              ),
            );
          }
        }

        if (zone.content == ZoneContent.singleSash ||
            zone.content == ZoneContent.doubleSash ||
            zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 8));
          final allowedDirections =
              (zone.content == ZoneContent.doubleSash ||
                  zone.content == ZoneContent.slidingSash ||
                  !widget.model.hasBottomFrame)
              ? [OpenDirection.left, OpenDirection.right]
              : OpenDirection.values;

          children.addAll(
            allowedDirections.map(
              (dir) => Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _ContentButton(
                  label: _getDirectionName(dir),
                  icon: Icons.open_with_rounded,
                  selected: zone.openDirection == dir,
                  onPressed: () =>
                      widget.model.setSelectedZoneOpenDirection(dir),
                ),
              ),
            ),
          );
        }

        if (zone.content == ZoneContent.singleSash ||
            zone.content == ZoneContent.doubleSash) {
          String btnLabel = Localization.translate('المقبض (Poignée)', lang);
          IconData btnIcon = Icons.door_back_door_rounded;
          bool btnSelected = false;

          if (zone.isSash105) {
            // Thick Sash (Door)
            if (zone.lockType == LockType.clef) {
              btnLabel = Localization.translate('مقبض الباب بمفتاح', lang);
              btnIcon = Icons.vpn_key_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.condamnation) {
              btnLabel = Localization.translate('مقبض الباب حمام', lang);
              btnIcon = Icons.lock_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.rouleau) {
              btnLabel = Localization.translate(
                'مقبض كبير ماريشال 1.25 متر',
                lang,
              );
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            } else if (zone.lockType == LockType.rouleau2000) {
              btnLabel = Localization.translate(
                'مقبض كبير ماريشال 2 متر',
                lang,
              );
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            } else if (zone.usePvcHandleOnAlu) {
              btnLabel = Localization.translate('Poignée fenêtre', lang);
              btnIcon = Icons.window_rounded;
              btnSelected = true;
            } else if (zone.useOctoHandle) {
              btnLabel = Localization.translate('مقبض أوكتو', lang);
              btnIcon = Icons.radio_button_checked_rounded;
              btnSelected = true;
            } else {
              // Default is Cremone on door
              btnLabel = Localization.translate('مقبض كريمون', lang);
              btnIcon = Icons.door_back_door_rounded;
              btnSelected = true;
            }
          } else {
            // Thin Sash (Window)
            if (zone.lockType == LockType.point) {
              btnLabel = Localization.translate('قفل نقطة', lang);
              btnIcon = Icons.adjust;
              btnSelected = true;
            } else if (zone.useOctoHandle) {
              btnLabel = Localization.translate('مقبض أوكتو', lang);
              btnIcon = Icons.radio_button_checked_rounded;
              btnSelected = true;
            } else {
              btnLabel = (widget.model.isPVC || zone.usePvcHandleOnAlu)
                  ? Localization.translate('Poignée fenêtre', lang)
                  : Localization.translate('مقبض كريمون', lang);
              btnIcon = Icons.window_rounded;
              btnSelected = true;
            }
          }

          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: btnLabel,
              icon: btnIcon,
              selected: btnSelected,
              onPressed: () {
                _setViewState(() {
                  _activeBottomTab = 5;
                });
              },
            ),
          );
        }
        if (zone.content == ZoneContent.slidingSash) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.useClassicHandle
                  ? Localization.translate('مقبض كلاسيكي (كودي)', lang)
                  : Localization.translate('مقبض منزلق (اندراماتيك)', lang),
              icon: Icons.sync_alt_rounded,
              selected: true,
              onPressed: () {
                _setViewState(() {
                  _activeBottomTab = 5;
                });
              },
            ),
          );
          if (isSlidingFaceToFaceLayout(
            trackCount: zone.slidingTrackCount,
            sashCount: zone.slidingSashesCount,
          )) {
            if (widget.model.supportsSlidingFaceToFace) {
              children.add(const SizedBox(width: 8));
              children.add(
                _ContentButton(
                  label: Localization.translate(
                    'التقاء الظرفتين الوسطيتين (Batmo central)',
                    lang,
                  ),
                  icon: Icons.layers_rounded,
                  selected: zone.slidingFaceToFace,
                  onPressed: () {
                    _setViewState(() {
                      widget.model.toggleSelectedZoneSlidingFaceToFace();
                    });
                  },
                ),
              );
            }
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: zone.slidingSecondCentralHandle
                    ? 'مقبض الوسط الشكلي: مفعّل'
                    : 'مقبض الوسط الشكلي: ملغي',
                icon: Icons.more_horiz_rounded,
                selected: zone.slidingSecondCentralHandle,
                enabled: zone.slidingFaceToFace,
                onPressed: () {
                  _setViewState(() {
                    widget.model.toggleSelectedZoneSlidingSecondCentralHandle();
                  });
                },
              ),
            );
          }
        }

        // Sub-zone cell options
        if (widget.model.activeSubZone != null &&
            widget.model.activeSubZone!.contains('cell_') &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          final cellKey = widget.model.activeSubZone!;
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.cellIsSash[cellKey] == true
                  ? 'دلفة داخلية (نشطة)'
                  : 'إضافة دلفة داخلية',
              icon: Icons.window,
              selected: zone.cellIsSash[cellKey] == true,
              onPressed: () {
                _setViewState(() {
                  widget.model.toggleSelectedCellSash();
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.cellIsDoubleSash[cellKey] == true
                  ? 'ضلفتان داخليتان (نشطة)'
                  : 'إضافة ضلفتان داخليتان',
              icon: Icons.window,
              selected: zone.cellIsDoubleSash[cellKey] == true,
              onPressed: () {
                _setViewState(() {
                  widget.model.toggleSelectedCellDoubleSash();
                });
              },
            ),
          );

          if (zone.cellIsSash[cellKey] == true ||
              zone.cellIsDoubleSash[cellKey] == true) {
            children.add(const SizedBox(width: 8));
            // Add 104/105 switch
            children.add(
              Builder(
                builder: (context) {
                  bool isCellSash105 = false;
                  final currentOverride = zone.cellSashOverrides[cellKey];
                  if (currentOverride != null) {
                    final code =
                        currentOverride['code']?.toString().toLowerCase() ?? '';
                    final name =
                        currentOverride['name']?.toString().toLowerCase() ?? '';
                    if (code.contains('104') || name.contains('104')) {
                      isCellSash105 = false;
                    } else if (code.contains('105') ||
                        code.contains('porte') ||
                        code.contains('ouvr') ||
                        name.contains('105') ||
                        name.contains('porte') ||
                        name.contains('ouvr') ||
                        name.contains('بورت')) {
                      isCellSash105 = true;
                    } else {
                      isCellSash105 = false;
                    }
                  } else {
                    isCellSash105 = zone.isSash105;
                  }

                  bool has104105Option = false;
                  if (activeSeriesForSystem != null) {
                    for (var sec in activeSeriesForSystem!.sections) {
                      if (sec.code.contains('104') ||
                          sec.code.contains('105') ||
                          sec.name.contains('104') ||
                          sec.name.contains('105')) {
                        has104105Option = true;
                        break;
                      }
                    }
                  }

                  if (!has104105Option) return const SizedBox.shrink();

                  return _ContentButton(
                    label: isCellSash105
                        ? 'الظلفة 105 (صندوق باب)'
                        : 'الظلفة 104 (نافذة)',
                    icon: Icons.swap_horiz,
                    selected: true,
                    onPressed: () async {
                      await widget.model.toggleCellSashType104105(cellKey);
                      _setViewState(() {});
                    },
                  );
                },
              ),
            );

            // Sub-sash opening direction
            children.add(const SizedBox(width: 8));
            children.add(
              Builder(
                builder: (context) {
                  final isDouble = zone.cellIsDoubleSash[cellKey] == true;
                  final currentDir = () {
                    final currentOverride = zone.cellSashOverrides[cellKey];
                    final defaultDir = isDouble
                        ? OpenDirection.right
                        : OpenDirection.left;
                    if (currentOverride != null &&
                        currentOverride['openDirection'] != null) {
                      final dirStr = currentOverride['openDirection']
                          .toString();
                      return OpenDirection.values.firstWhere(
                        (d) => d.name == dirStr,
                        orElse: () => defaultDir,
                      );
                    }
                    return defaultDir;
                  }();

                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ...(isDouble
                              ? [OpenDirection.left, OpenDirection.right]
                              : OpenDirection.values)
                          .map(
                            (dir) => Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: _ContentButton(
                                label: _getDirectionName(dir),
                                icon: Icons.open_with_rounded,
                                selected: currentDir == dir,
                                onPressed: () {
                                  _setViewState(() {
                                    widget.model.setCellSashOpenDirection(
                                      cellKey,
                                      dir,
                                    );
                                  });
                                },
                              ),
                            ),
                          ),
                    ],
                  );
                },
              ),
            );
          }
        }
        if (!widget.model.isPVC &&
            (zone.content == ZoneContent.singleSash ||
                zone.content == ZoneContent.doubleSash)) {
          children.add(const SizedBox(width: 8));
          children.add(
            _ContentButton(
              label: zone.hasSashPlintheBottom
                  ? 'حذف بلانت الضلفة'
                  : 'إضافة بلانت للضلفة',
              icon: Icons.border_bottom_rounded,
              selected: zone.hasSashPlintheBottom,
              onPressed: () {
                _setViewState(() {
                  widget.model.toggleSelectedZoneSashPlintheBottom();
                });
              },
            ),
          );
        }
        break;

      case 3: // عامود (Mullion settings)
        if (isMullionSelected) {
          String key =
              "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(1)}";
          MullionProfileType currentType =
              widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
          final canFlipGroove =
              currentType == MullionProfileType.grooved &&
              widget.model.selection.isHorizontalMullion != null &&
              widget.model.selection.mullionPosition != null;

          children.add(
            _ContentButton(
              label: 'حذف العامود',
              icon: Icons.delete_forever_rounded,
              selected: false,
              onPressed: () {
                _setViewState(() {
                  widget.model.deleteSelectedMullion();
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Traverse',
              icon: Icons.horizontal_rule_rounded,
              selected: currentType == MullionProfileType.standard,
              onPressed: () {
                _setViewState(() {
                  widget.model.setMullionProfile(MullionProfileType.standard);
                });
              },
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Cadre doublé',
              icon: Icons.splitscreen_rounded,
              selected: currentType == MullionProfileType.flat,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.flat,
              ),
            ),
          );
          children.add(const SizedBox(width: 8));

          children.add(
            _ContentButton(
              label: 'Cadre 140',
              icon: Icons.view_headline_rounded,
              selected: currentType == MullionProfileType.grooved,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.grooved,
              ),
            ),
          );
          if (canFlipGroove) {
            children.add(const SizedBox(width: 8));
            children.add(
              _ContentButton(
                label: 'قلب جهة حامل الزجاج',
                icon: Icons.swap_horiz_rounded,
                selected: widget.model.isGroovedMullionCavityOnPositiveSide(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
                onPressed: () {
                  _setViewState(() {
                    widget.model.toggleGroovedMullionCavity(
                      widget.model.selection.isHorizontalMullion!,
                      widget.model.selection.mullionPosition!,
                    );
                  });
                },
              ),
            );
          }
        } else {
          children.add(
            const Text(
              'الرجاء تحديد عامود من الرسم بالضغط عليه لتعديله',
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        }
        break;

      case 4: // زجاج / حشوات (Glass settings)
        final GlassSpecification spec = zone != null
            ? (widget.model.activeSubZone != null
                  ? zone.getGlassForCell(widget.model.activeSubZone)
                  : zone.glass)
            : const GlassSpecification();

        final bool isSliding =
            widget.systemMode == 'sliding' ||
            (widget.systemMode == 'mixed' &&
                zone != null &&
                zone.content == ZoneContent.slidingSash);
        if (!isSliding) {
          final parcloseOverride =
              widget.model.componentOverrides['باكيت الزجاج (Parclose)'];
          final parcloseLabel = parcloseOverride != null
              ? '${Localization.translate('Parclose', lang)}: ${parcloseOverride['code']} (${(parcloseOverride['max_glass_thickness'] as num?)?.toDouble() ?? 0.0} ${Localization.translate('مم', lang)})'
              : Localization.translate('Choisir la parclose', lang);
          children.add(
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: _ContentButton(
                label: parcloseLabel,
                icon: Icons.border_outer_rounded,
                selected: parcloseOverride != null,
                onPressed: () => _showParcloseSelectorDialog(context),
              ),
            ),
          );
          children.add(const SizedBox(width: 12));
        }

        String getGlassDescription(GlassSpecification spec, AppLanguage lang) {
          String structName = '';
          switch (spec.structure) {
            case GlassStructure.simple:
              structName = Localization.translate('عادي', lang);
              break;
            case GlassStructure.double:
              structName = Localization.translate('مزدوج', lang);
              break;
            case GlassStructure.closed:
              structName = Localization.translate('بانو', lang);
              break;
          }

          if (spec.structure == GlassStructure.double) {
            final double tOuter =
                spec.thicknessOuter ?? kDefaultGlassPaneThickness;
            final int intercall = spec.intercallThickness;
            final double tInner =
                spec.thicknessInner ?? kDefaultGlassPaneThickness;
            structName += ' (${tOuter.toInt()}-${intercall}-${tInner.toInt()})';
          }

          String finishName = '';
          if (spec.structure == GlassStructure.closed) {
            finishName = Localization.translate(
              widget.model.getClosedColoreName(spec.colorP),
              lang,
            );
          } else {
            finishName = Localization.translate(
              widget.model.getFinishName(spec.finishOuter),
              lang,
            );
            if (spec.finishOuter == GlassFinish.stopSol) {
              final String colName = Localization.translate(
                widget.model.getArabicColorName(spec.colorOuter),
                lang,
              );
              finishName += ' ($colName)';
            }
          }
          if (finishName.isNotEmpty) {
            structName += ' - $finishName';
          }
          return structName;
        }

        final isDark = Theme.of(context).brightness == Brightness.dark;
        final String glassDesc = getGlassDescription(spec, lang);

        children.add(
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: isDark
                    ? const Color(0xFF1E1E2C)
                    : Colors.blue.shade50.withOpacity(0.5),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: isDark ? Colors.blue.shade800 : Colors.blue.shade100,
                  width: 1.0,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.info_outline_rounded,
                    size: 16,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade800,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${Localization.translate('الزجاج الحالي', lang)}: $glassDesc',
                    style: TextStyle(
                      color: isDark ? Colors.white : Colors.blue.shade900,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );

        children.add(const SizedBox(width: 12));
        children.add(
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: _ContentButton(
              label: Localization.translate('تخصيص مظهر الزجاج', lang),
              icon: Icons.edit_note_rounded,
              selected: true,
              onPressed: () {
                _setViewState(() {
                  _isLeftDrawerOpen = true;
                });
              },
            ),
          ),
        );

        break;

      case 5: // مقابض (Handles/Locks settings)
        if (zone.content != ZoneContent.singleSash &&
            zone.content != ZoneContent.doubleSash &&
            zone.content != ZoneContent.slidingSash) {
          children.add(
            Text(
              Localization.translate(
                'الرجاء تحديد ضلفة من الرسم لتعديل مقابضها',
                lang,
              ),
              style: const TextStyle(color: Colors.grey, fontSize: 12),
            ),
          );
        } else {
          // The selected profile is the source of truth.  A thick profile can
          // be selected inside a divided double sash before the old zone flag
          // is refreshed, so checking only `zone.isSash105` hid all door
          // handle buttons and left only the optional two-handle button.
          final isDoorSash = widget.model.selectedZoneUsesSash105;
          if (zone.content == ZoneContent.slidingSash) {
            children.add(_buildRuleHandles(zone));
          } else if (widget.model.isPVC) {
            if (isDoorSash) {
              // PVC Door sashes
              // 1. Key handle. A shutter does not remove door-handle choices.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب بمفتاح', lang),
                    icon: Icons.vpn_key_rounded,
                    selected: zone.lockType == LockType.clef,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.clef,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 2. Bathroom handle. A shutter does not remove door-handle choices.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب حمام', lang),
                    icon: Icons.lock_rounded,
                    selected: zone.lockType == LockType.condamnation,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.condamnation,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 3. A thick sash can also use the ordinary window handle.
              children.add(
                _ContentButton(
                  label: Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                      zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    _setViewState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              // 4. Maréchal handle (if no bottom frame AND no roller shutter)
              if (widget.model.hasBottomFrame == false &&
                  widget.model.hasShutter == false) {
                final double doorHeight = zone.boundary.height;
                if (doorHeight >= 1250.0) {
                  children.add(
                    _ContentButton(
                      label: Localization.translate(
                        'مقبض كبير ماريشال 1.25 متر',
                        lang,
                      ),
                      icon: Icons.door_back_door_rounded,
                      selected: zone.lockType == LockType.rouleau,
                      onPressed: () {
                        _setViewState(() {
                          widget.model.setSelectedZoneHandle(
                            lockType: LockType.rouleau,
                          );
                        });
                      },
                    ),
                  );
                  children.add(const SizedBox(width: 8));

                  if (doorHeight > 2000.0) {
                    children.add(
                      _ContentButton(
                        label: Localization.translate(
                          'مقبض كبير ماريشال 2 متر',
                          lang,
                        ),
                        icon: Icons.door_back_door_rounded,
                        selected: zone.lockType == LockType.rouleau2000,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.setSelectedZoneHandle(
                              lockType: LockType.rouleau2000,
                            );
                          });
                        },
                      ),
                    );
                  }
                }
              }
            } else {
              // PVC Window sashes
              if (zone.content == ZoneContent.doubleSash) {
                // Double sash PVC window: only window handle (x2)
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض نافذة', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle != true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
              } else {
                // Single sash PVC window: window handle, and Octo handle
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض نافذة', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle != true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle == true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
              }
            }
          } else {
            // Aluminium Swing Sashes
            if (isDoorSash) {
              // Door sashes (Thick Sash / الظلفة الغليظة)

              // 1. Cremone handle (مقبض كريمون)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('مقبض كريمون', lang)
                      : Localization.translate('مقبض كريمون', lang),
                  icon: Icons.door_back_door_rounded,
                  selected:
                      zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu != true,
                  onPressed: () {
                    _setViewState(() {
                      widget.model.setSelectedZoneHandle();
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              // 2. Key handle (مقبض الباب بمفتاح), including shutter windows.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب بمفتاح', lang),
                    icon: Icons.vpn_key_rounded,
                    selected: zone.lockType == LockType.clef,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.clef,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 3. Bathroom handle (مقبض الباب حمام), including shutter windows.
              if (zone.content != ZoneContent.slidingSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض الباب حمام', lang),
                    icon: Icons.lock_rounded,
                    selected: zone.lockType == LockType.condamnation,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.condamnation,
                        );
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 4. Octo handle (مقبض أوكتو - single-sash only)
              if (zone.content == ZoneContent.singleSash) {
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle == true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));
              }

              // 5. Maréchal handle (if no bottom frame AND no roller shutter)
              if (widget.model.hasBottomFrame == false &&
                  widget.model.hasShutter == false) {
                final double doorHeight = zone.boundary.height;
                if (doorHeight >= 1250.0) {
                  children.add(
                    _ContentButton(
                      label: Localization.translate(
                        'مقبض كبير ماريشال 1.25 متر',
                        lang,
                      ),
                      icon: Icons.door_back_door_rounded,
                      selected: zone.lockType == LockType.rouleau,
                      onPressed: () {
                        _setViewState(() {
                          widget.model.setSelectedZoneHandle(
                            lockType: LockType.rouleau,
                          );
                        });
                      },
                    ),
                  );
                  children.add(const SizedBox(width: 8));

                  if (doorHeight > 2000.0) {
                    children.add(
                      _ContentButton(
                        label: Localization.translate(
                          'مقبض كبير ماريشال 2 متر',
                          lang,
                        ),
                        icon: Icons.door_back_door_rounded,
                        selected: zone.lockType == LockType.rouleau2000,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.setSelectedZoneHandle(
                              lockType: LockType.rouleau2000,
                            );
                          });
                        },
                      ),
                    );
                    children.add(const SizedBox(width: 8));
                  }
                }
              }

              // Window handle (Poignée fenêtre)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('Poignée fenêtre', lang)
                      : Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                      zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    _setViewState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
            } else {
              // Window sashes (Thin Sash / الظلفة الرقيقة)
              // Window handle (Poignée fenêtre)
              children.add(
                _ContentButton(
                  label: zone.content == ZoneContent.doubleSash
                      ? Localization.translate('Poignée fenêtre', lang)
                      : Localization.translate('Poignée fenêtre', lang),
                  icon: Icons.window_rounded,
                  selected:
                      zone.lockType == LockType.none &&
                      zone.useOctoHandle != true &&
                      zone.usePvcHandleOnAlu == true,
                  onPressed: () {
                    _setViewState(() {
                      widget.model.setSelectedZoneHandle(
                        usePvcHandleOnAlu: true,
                      );
                    });
                  },
                ),
              );
              children.add(const SizedBox(width: 8));

              if (zone.content == ZoneContent.doubleSash) {
                // Cremone x2
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض كريمون', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle != true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
              } else {
                // Single sash: Cremone, Octo, Point Lock
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض كريمون', lang),
                    icon: Icons.door_back_door_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle != true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle();
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                // Octo
                children.add(
                  _ContentButton(
                    label: Localization.translate('مقبض أوكتو', lang),
                    icon: Icons.radio_button_checked_rounded,
                    selected:
                        zone.lockType == LockType.none &&
                        zone.useOctoHandle == true &&
                        zone.usePvcHandleOnAlu != true,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(useOctoHandle: true);
                      });
                    },
                  ),
                );
                children.add(const SizedBox(width: 8));

                // Point Lock
                children.add(
                  _ContentButton(
                    label: Localization.translate('قفل نقطة', lang),
                    icon: Icons.adjust,
                    selected: zone.lockType == LockType.point,
                    onPressed: () {
                      _setViewState(() {
                        widget.model.setSelectedZoneHandle(
                          lockType: LockType.point,
                        );
                      });
                    },
                  ),
                );
              }
            }
          }
        }
        if (zone.content == ZoneContent.doubleSash) {
          children.add(const SizedBox(width: 8));
          final twoHandlesLabel = switch (lang) {
            AppLanguage.arabic => 'إضافة مقبضين',
            AppLanguage.french => 'Ajouter deux poignées',
            AppLanguage.english => 'Add two handles',
          };
          children.add(
            _ContentButton(
              label: twoHandlesLabel,
              icon: Icons.pan_tool_alt_rounded,
              selected: zone.doubleSashHasTwoHandles,
              onPressed: () {
                _setViewState(() {
                  widget.model.setSelectedZoneDoubleHandles(
                    !zone.doubleSashHasTwoHandles,
                  );
                });
              },
            ),
          );
        }
        children.add(const SizedBox(width: 12));
        children.add(
          SizedBox(
            width: 250,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  Localization.translate('ارتفاع المقبض', lang),
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                Slider(
                  value: (zone.handlePositionRatio ?? 0.5).clamp(0.1, 0.9),
                  min: 0.1,
                  max: 0.9,
                  divisions: 80,
                  onChanged: (value) =>
                      widget.model.updateHandlePosition(zone.id, value),
                ),
              ],
            ),
          ),
        );
        break;
    }

    return children;
  }

  Widget _buildCollapsedStatusBar(BuildContext context) {
    final zone = widget.model.selectedZone;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
        border: Border(
          top: BorderSide(
            color: isDark ? Colors.grey.shade800 : Colors.grey.shade200,
          ),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  zone == null
                      ? Localization.translate(
                          'انقر لتحديد وتعديل أي منطقة',
                          lang,
                        )
                      : '${Localization.translate('المنطقة المحددة', lang)}: ${Localization.translate(zone.content.name, lang)}  |  ${Localization.translate('الأبعاد', lang)}: ${zone.boundary.width.toInt()} × ${zone.boundary.height.toInt()} mm',
                  style: TextStyle(
                    color: isDark ? Colors.white70 : Colors.black54,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: isDark
                                ? Colors.green.shade700
                                : Colors.green,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () =>
                              _openMaterialConsumptionScreen(context),
                          child: Text(
                            Localization.translate('الكمية والتكلفة', lang),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.blue.shade700,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 10),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          onPressed: () => _addDrawingAndCalculate(context),
                          icon: const Icon(
                            Icons.add_shopping_cart_rounded,
                            size: 17,
                          ),
                          label: Text(
                            Localization.translate('إضافة واحتساب السعر', lang),
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
