part of '../show_system_francais.dart';

/// Sliding leaves, tracks and montants controls of the drawing page.
extension _WindowViewSliding on _WindowViewState {
  Widget _buildRuleHandles(WindowZone zone) {
    final seriesId = widget.model.effectiveSlidingSeries?.id;
    if (_handleCandidates == null || _handleSeriesId != seriesId) {
      _handleSeriesId = seriesId;
      _handleCandidates = seriesId == null
          ? Future.value(<Map<String, dynamic>>[])
          : CatalogCandidateResolver(database: SqlDatabase()).resolve(
              CatalogCandidateQuery(
                category: 'accessory',
                selectorType: '',
                roleKeys: const [
                  'handle',
                  'entrematique',
                  'poignee_encastree',
                ],
                seriesId: seriesId,
                materialType: widget.model.isSlidingPVC ? 'pvc' : 'aluminium',
                drawingMode: AccessoryDrawingMode.sliding,
                requireDialog: true,
                requireQuantity: true,
              ),
            );
    }
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: _handleCandidates,
      builder: (context, snapshot) {
        if (snapshot.hasError) return const Text('تعذر تحميل قواعد المقابض');
        if (!snapshot.hasData)
          return const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(),
          );
        final pvc = widget.model.usesPvcSlidingHandles;
        final available = widget.model.availableSlidingHandleTypes;
        String typeOf(Map<String, dynamic> candidate) =>
            SlidingHandleType.fromRole(
              (candidate['catalog_rule'] as Map)['role_key']?.toString(),
              pvc: pvc,
            );
        final candidates = snapshot.data!.where((candidate) {
          final rule = candidate['catalog_rule'];
          return rule is Map &&
              rule['show_in_drawing'] != 0 &&
              rule['show_in_drawing'] != false &&
              // A PVC sliding window never takes an entrematique.
              available.contains(typeOf(candidate));
        }).toList();
        if (candidates.isEmpty)
          return const Text('لا توجد مقابض مفعّلة لهذه السلسلة');
        // The handle places the choice applies to: the tapped leaf's handle,
        // the whole window, or every sliding window after a long press.
        final targets = widget.model.selectedSlidingHandleSlots;
        final targetSlots = targets[zone] ?? const <String>[];
        final placeLabel = widget.model.allSashesSelected
            ? _tr('كل المقابض')
            : targetSlots.length == 1
            ? switch (targetSlots.single) {
                SlidingHandleType.left => _tr('المقبض الأيسر'),
                SlidingHandleType.right => _tr('المقبض الأيمن'),
                _ => _tr('مقابض الوسط'),
              }
            : _tr('كل مقابض النافذة');
        final handleButtons = Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              '$placeLabel:',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            ...candidates.map((candidate) {
              final type = typeOf(candidate);
              final key = SlidingHandleType.accessoryKey(type);
              return _ContentButton(
                label: '${candidate['name'] ?? candidate['code'] ?? ''}',
                icon: Icons.sync_alt_rounded,
                selected:
                    targetSlots.isNotEmpty &&
                    targetSlots.every(
                      (slot) =>
                          widget.model.slidingHandleTypeFor(zone, slot) == type,
                    ) &&
                    widget.model.componentOverrides[key]?['id'] ==
                        candidate['id'],
                onPressed: () {
                  widget.model.componentOverrides[key] =
                      Map<String, dynamic>.from(candidate);
                  widget.model.setSelectedSlidingHandleType(type);
                  _setViewState(() {});
                },
              );
            }),
          ],
        );
        if (!isSlidingFaceToFaceLayout(
          trackCount: zone.slidingTrackCount,
          sashCount: zone.slidingSashesCount,
        )) {
          return handleButtons;
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            handleButtons,
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                if (widget.model.supportsSlidingFaceToFace)
                  _ContentButton(
                    label: 'التقاء الوسط (Face-to-Face)',
                    icon: Icons.layers_rounded,
                    selected: zone.slidingFaceToFace,
                    onPressed: () {
                      widget.model.toggleSelectedZoneSlidingFaceToFace();
                      _setViewState(() {});
                    },
                  ),
                _ContentButton(
                  label: zone.slidingSecondCentralHandle
                      ? 'مقبض الوسط الشكلي: مفعّل'
                      : 'مقبض الوسط الشكلي: ملغي',
                  icon: Icons.more_horiz_rounded,
                  selected: zone.slidingSecondCentralHandle,
                  enabled: zone.slidingFaceToFace,
                  onPressed: () {
                    widget.model.toggleSelectedZoneSlidingSecondCentralHandle();
                    _setViewState(() {});
                  },
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  String _trackCountLabel(int count, AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => '$count سكك',
    AppLanguage.french => '$count rails',
    _ => '$count tracks',
  };

  String _trackTitle(AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'عدد السكك في الإطار:',
    AppLanguage.french => 'Nombre de rails du cadre :',
    _ => 'Frame track count:',
  };

  String _trackShortTitle(AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'السكك:',
    AppLanguage.french => 'Rails :',
    _ => 'Tracks:',
  };

  String _slidingCountLabel(int count, AppLanguage lang) => switch (lang) {
    AppLanguage.arabic => 'منزلق $count',
    AppLanguage.french => 'Coulissant $count vantaux',
    _ => '$count-sash sliding',
  };

  String _frameTrackCompositionLabel(
    int trackCount,
    bool complete,
    AppLanguage lang,
  ) {
    if (complete) {
      return switch (lang) {
        AppLanguage.arabic => 'إطار كامل بـ $trackCount سكك',
        AppLanguage.french => 'Cadre complet à $trackCount rails',
        _ => 'Complete $trackCount-track frame',
      };
    }
    if (trackCount <= 2) {
      return switch (lang) {
        AppLanguage.arabic => 'إطار أساسي بسكتين',
        AppLanguage.french => 'Cadre de base à 2 rails',
        _ => 'Two-track base frame',
      };
    }
    final additions = trackCount - 2;
    return switch (lang) {
      AppLanguage.arabic => 'إطار أساسي بسكتين + $additions سكة إضافية',
      AppLanguage.french =>
        'Cadre de base à 2 rails + $additions rail(s) ajouté(s)',
      _ =>
        'Two-track base frame + $additions additional track(s)',
    };
  }

  bool get isSlidingSupported {
    if (widget.systemMode == 'mixed') {
      final system = profileSystemForSeries(
        widget.model.availableSystems,
        widget.model.activeSeries ?? widget.model.activeSlidingSeries,
      );
      return system != null && _seriesForScope(system, 'sliding').isNotEmpty;
    }

    if (widget.systemMode != 'sliding') return false;
    final series = widget.model.activeSlidingSeries;
    if (series == null) return false;
    final system = profileSystemForSeries(
      widget.model.availableSystems,
      series,
    );
    return system != null && _seriesForScope(system, 'sliding').isNotEmpty;
  }

  /// PVC has no reinforced sliding montant. Keep this rule at the drawing
  /// level so an old saved flag cannot bring reinforcement controls back.
  bool get _pvcMontantReinforcementDisabled =>
      widget.model.isPVC ||
      widget.model.isSlidingPVC ||
      _seriesIsPvc(widget.model.activeSlidingSeries);

  void _showSlidingUnsupportedSnack() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
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
  }

  Future<void> _setSelectedZoneSlidingSashesFromUi(int count) async {
    final zone = widget.model.selectedZone;
    if (zone == null) return;
    if (widget.model.hasArchOrSlant) {
      _showSlidingUnsupportedSnack();
      return;
    }
    final cutRebate = await _askSlidingRebateCut(zone);
    if (!mounted) return;
    _setViewState(() {
      widget.model.setSelectedZoneSlidingSashes(
        count,
        cutSlidingGlassRebate: cutRebate,
      );
    });
  }

  void _queueMixedSlidingSeriesSelection(
    AluminumSeries candidate,
    int? openingSeriesId,
  ) {
    if (_slidingSeriesAutoSelectionQueued) return;
    _slidingSeriesAutoSelectionQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      try {
        if (!mounted ||
            widget.model.activeSeries?.id != openingSeriesId ||
            widget.model.activeSlidingSeries != null ||
            widget.model.activeSlidingSeries?.id == candidate.id) {
          return;
        }
        widget.model.systemMode = 'mixed';
        await widget.model.setActiveSlidingSeries(candidate);
      } finally {
        _slidingSeriesAutoSelectionQueued = false;
      }
    });
  }

  bool _isReinforcedMontant(
    Map<String, dynamic> item, {
    required bool central,
  }) {
    return widget.model.isSlidingMontantReinforced(item, central: central);
  }

  bool _isSlidingMontantCandidate(
    Map<String, dynamic> item, {
    required bool central,
  }) {
    return widget.model.isSlidingMontantCandidate(item, central: central);
  }

  Future<void> _syncSlidingMontantOverrideFromFlags({
    required bool central,
  }) async {
    if (_pvcMontantReinforcementDisabled) return;

    final hasReinforced = central
        ? widget.model.zones.any(
            (zone) => zone.slidingMontantReinforced.entries.any(
              (entry) => entry.key.startsWith('central_') && entry.value,
            ),
          )
        : widget.model.zones.any(
            (zone) => zone.slidingMontantReinforced.entries.any(
              (entry) => entry.key.startsWith('lateral_') && entry.value,
            ),
          );

    final hasNormal = central
        ? widget.model.zones.any((zone) {
            if (zone.content != ZoneContent.slidingSash) return false;
            final sashes = zone.slidingSashesCount > 0
                ? zone.slidingSashesCount
                : 2;
            final bool hasMeetingInCenter =
                zone.slidingFaceToFace &&
                isSlidingFaceToFaceLayout(
                  trackCount: zone.slidingTrackCount,
                  sashCount: sashes,
                );
            final centralCount = hasMeetingInCenter
                ? (sashes == 4 ? 4 : 8)
                : math.max(0, (sashes * 2) - 2);
            for (var i = 0; i < centralCount; i++) {
              if (zone.slidingMontantReinforced['central_$i'] != true) {
                return true;
              }
            }
            return false;
          })
        : widget.model.zones.any((zone) {
            if (zone.content != ZoneContent.slidingSash) return false;
            final sashes = zone.slidingSashesCount > 0
                ? zone.slidingSashesCount
                : 2;
            final bool hasMeetingInCenter =
                zone.slidingFaceToFace &&
                isSlidingFaceToFaceLayout(
                  trackCount: zone.slidingTrackCount,
                  sashCount: sashes,
                );
            final lateralCount = hasMeetingInCenter ? 4 : 2;
            for (var i = 0; i < lateralCount; i++) {
              if (zone.slidingMontantReinforced['lateral_$i'] != true) {
                return true;
              }
            }
            return false;
          });

    final allCandidates =
        <Map<String, dynamic>>[
              ..._sashProfiles,
              ..._slidingSashProfiles,
              ...?(widget.model.effectiveSlidingSeries ??
                      widget.model.activeSlidingSeries)
                  ?.sections
                  .map((s) => s.toMap()),
            ]
            .where((item) => _isSlidingMontantCandidate(item, central: central))
            .toList();

    if (allCandidates.isEmpty) return;

    final reinforcedKey = central
        ? 'قائم وسطي معزز (Sash Central Renforcé)'
        : 'قائم جانبي معزز (Sash Lateral Renforcé)';
    final normalKey = central
        ? 'قائم وسطي (Sash Central)'
        : 'قائم جانبي (Sash Lateral)';

    if (hasReinforced) {
      if (!widget.model.componentOverrides.containsKey(reinforcedKey)) {
        var rCandidates = allCandidates
            .where((item) => _isReinforcedMontant(item, central: central))
            .toList();
        if (rCandidates.isEmpty && central) {
          final chicaneCandidates = allCandidates.where((item) {
            final t =
                '${item['type'] ?? ''} ${item['name'] ?? ''} ${item['design_role_key'] ?? ''}'
                    .toLowerCase();
            return t.contains('chicane') ||
                t.contains('شيكان') ||
                t.contains('renforc') ||
                t.contains('معزز');
          }).toList();
          if (chicaneCandidates.isNotEmpty) rCandidates = chicaneCandidates;
        }
        if (rCandidates.isNotEmpty) {
          final selected = Map<String, dynamic>.from(rCandidates.first);
          selected['calculated_price'] = await _sectionPriceForSelectedColor(
            selected,
          );
          widget.model.applySlidingMontantOverride(
            selected,
            central: central,
            reinforced: true,
            manualSelection: true,
            updateAllMembers: false,
          );
        }
      }
    } else {
      widget.model.componentOverrides.remove(reinforcedKey);
    }

    if (hasNormal) {
      final hasAnyNormalOverride =
          widget.model.componentOverrides.containsKey(normalKey) ||
          widget.model.componentOverrides.containsKey(
            central ? 'قائم وسطي (Central)' : 'قائم جانبي (Lateral)',
          );
      if (!hasAnyNormalOverride) {
        final nCandidates = allCandidates
            .where((item) => !_isReinforcedMontant(item, central: central))
            .toList();
        if (nCandidates.isNotEmpty) {
          final selected = Map<String, dynamic>.from(nCandidates.first);
          selected['calculated_price'] = await _sectionPriceForSelectedColor(
            selected,
          );
          widget.model.applySlidingMontantOverride(
            selected,
            central: central,
            reinforced: false,
            manualSelection: true,
            updateAllMembers: false,
          );
        }
      }
    } else {
      widget.model.componentOverrides.remove(normalKey);
      widget.model.componentOverrides.remove(
        central ? 'قائم وسطي (Central)' : 'قائم جانبي (Lateral)',
      );
    }

    if (!mounted) return;
    _setViewState(() {
      widget.model.refreshUI();
    });
  }
}
