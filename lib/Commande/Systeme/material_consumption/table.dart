part of '../material_consumption_screen.dart';

/// The material table: rows, columns, drag and layout.
extension _MaterialTable on _MaterialConsumptionScreenState {
  String _bomRowSearchText(BomItem item) =>
      '${item.originalName} ${item.name} ${item.profileCode ?? ''}'
          .toLowerCase();

  bool _bomRowMentionsCatalog(BomItem item, Map<String, dynamic>? catalog) {
    if (catalog == null) return false;
    final rowText = _bomRowSearchText(item);
    final code = '${catalog['code'] ?? ''}'.trim().toLowerCase();
    final name = '${catalog['name'] ?? ''}'.trim().toLowerCase();
    if (code.isNotEmpty && rowText.contains(code)) return true;
    return name.isNotEmpty && rowText.contains(name);
  }

  bool get _desktopTableMode => MediaQuery.sizeOf(context).width >= 900;

  void _handleTablePageWheel(PointerSignalEvent event) {
    if (event is! PointerScrollEvent ||
        event.scrollDelta.dy == 0 ||
        !_pageScrollController.hasClients) {
      return;
    }
    // Only claim the wheel when the page can still move; at an edge the
    // event must stay available to the table or another scrollable.
    final current = _pageScrollController.position;
    if (!current.hasContentDimensions) return;
    final target = (current.pixels + event.scrollDelta.dy).clamp(
      current.minScrollExtent,
      current.maxScrollExtent,
    );
    if ((target - current.pixels).abs() < 0.5) return;
    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted || !_pageScrollController.hasClients) return;
      final position = _pageScrollController.position;
      if (!position.hasContentDimensions) return;
      final newOffset = (position.pixels + event.scrollDelta.dy).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );
      if ((newOffset - position.pixels).abs() >= 0.5) {
        position.pointerScroll(event.scrollDelta.dy);
      }
    });
  }

  String _tableSectionForItem(BomItem item) {
    if (item.category == 'profile') return 'profile';
    if (item.category == 'joint') return 'joint';
    if (item.category == 'moustiquaire') return 'moustiquaire';
    if (item.category == 'glass' || item.category == 'panneau') {
      return 'glass';
    }
    if (item.category == 'shutter' || _isBouchonLameBomItem(item)) {
      return 'shutter';
    }
    return 'accessory';
  }

  String _materialRowKey(BomItem item) => [
    item.category,
    item.kitGroupName ?? '',
    item.originalName,
    item.name,
    item.unit,
    item.catalogItemId ?? '',
  ].join('|');

  String _materialDragId(BomItem item) =>
      '${_tableSectionForItem(item)}\u0000${_materialRowKey(item)}';

  List<BomItem> _orderedMaterialItems(String section, List<BomItem> items) {
    final byKey = <String, BomItem>{
      for (final item in items) _materialRowKey(item): item,
    };
    final stored = _manualTableOrder[section] ?? const <String>[];
    final used = <String>{};
    final ordered = <BomItem>[];
    for (final key in stored) {
      final item = byKey[key];
      if (item != null && used.add(key)) ordered.add(item);
    }
    for (final item in items) {
      final key = _materialRowKey(item);
      if (used.add(key)) ordered.add(item);
    }
    return ordered;
  }

  void _moveMaterialRow(String sourceId, String targetId) {
    final sourceSeparator = sourceId.indexOf('\u0000');
    final targetSeparator = targetId.indexOf('\u0000');
    if (sourceSeparator <= 0 || targetSeparator <= 0) return;
    final sourceSection = sourceId.substring(0, sourceSeparator);
    final targetSection = targetId.substring(0, targetSeparator);
    if (sourceSection != targetSection) return;
    final sourceKey = sourceId.substring(sourceSeparator + 1);
    final targetKey = targetId.substring(targetSeparator + 1);
    final sectionItems = _visibleBomItems
        .where((item) => _tableSectionForItem(item) == sourceSection)
        .toList();
    final source = sectionItems.firstWhere(
      (item) => _materialRowKey(item) == sourceKey,
      orElse: () => sectionItems.first,
    );
    final target = sectionItems.firstWhere(
      (item) => _materialRowKey(item) == targetKey,
      orElse: () => sectionItems.first,
    );
    // Keep a kit's children together and allow independent rows to be
    // reordered among themselves.  This prevents a child from visually
    // escaping its kit group.
    if ((source.kitGroupName ?? '') != (target.kitGroupName ?? '')) return;
    final keys = _orderedMaterialItems(
      sourceSection,
      sectionItems,
    ).map(_materialRowKey).toList();
    final oldIndex = keys.indexOf(sourceKey);
    final targetIndex = keys.indexOf(targetKey);
    if (oldIndex < 0 || targetIndex < 0 || oldIndex == targetIndex) return;
    final moved = keys.removeAt(oldIndex);
    keys.insert(targetIndex, moved);
    _setScreenState(() => _manualTableOrder[sourceSection] = keys);
  }

  Widget _buildDraggableMaterialRow(BomItem item) {
    if (!_desktopTableMode) return _row(item);
    final dragId = _materialDragId(item);
    return DragTarget<String>(
      onWillAcceptWithDetails: (details) => details.data != dragId,
      onAcceptWithDetails: (details) => _moveMaterialRow(details.data, dragId),
      builder: (context, candidates, rejected) {
        final isTarget = candidates.isNotEmpty;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          decoration: isTarget
              ? BoxDecoration(
                  border: Border.all(color: Colors.lightBlue, width: 2),
                )
              : null,
          child: LongPressDraggable<String>(
            data: dragId,
            axis: Axis.vertical,
            feedback: Material(
              color: Colors.transparent,
              elevation: 8,
              child: SizedBox(width: _minW, child: _row(item)),
            ),
            childWhenDragging: Opacity(opacity: 0.28, child: _row(item)),
            child: Stack(
              children: [
                _row(item),
                const PositionedDirectional(
                  top: 0,
                  end: 2,
                  bottom: 0,
                  child: IgnorePointer(
                    child: Center(
                      child: Icon(
                        Icons.drag_indicator_rounded,
                        size: 22,
                        color: Colors.blueGrey,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  double _columnWidth(String key, double fallback) =>
      _tableColumnWidths[key] ?? fallback;

  double get _frozenWidth => _wName;

  double _columnMinWidth(String key) {
    switch (key) {
      case _MaterialConsumptionScreenState._colImg:
        return 46;
      case _MaterialConsumptionScreenState._colName:
        return 150;
      case _MaterialConsumptionScreenState._colQty:
      case _MaterialConsumptionScreenState._colCheck:
        return 70;
      case _MaterialConsumptionScreenState._colActualMeters:
        return 95;
      case _MaterialConsumptionScreenState._colPrice:
      case _MaterialConsumptionScreenState._colEstimated:
      case _MaterialConsumptionScreenState._colTotal:
        return 105;
      default:
        return 85;
    }
  }

  double _columnMaxWidth(String key) {
    switch (key) {
      case _MaterialConsumptionScreenState._colName:
        return 520;
      case _MaterialConsumptionScreenState._colColor:
        return 260;
      default:
        return 320;
    }
  }

  double _defaultColumnWidth(String key) {
    switch (key) {
      case _MaterialConsumptionScreenState._colImg:
        return _MaterialConsumptionScreenState._defaultWImg;
      case _MaterialConsumptionScreenState._colName:
        return _MaterialConsumptionScreenState._defaultWName;
      case _MaterialConsumptionScreenState._colQty:
        return _MaterialConsumptionScreenState._defaultWQty;
      case _MaterialConsumptionScreenState._colActualMeters:
        return _MaterialConsumptionScreenState._defaultWActualMeters;
      case _MaterialConsumptionScreenState._colPrice:
        return _MaterialConsumptionScreenState._defaultWPrice;
      case _MaterialConsumptionScreenState._colEstimated:
        return _MaterialConsumptionScreenState._defaultWEstimated;
      case _MaterialConsumptionScreenState._colTotal:
        return _MaterialConsumptionScreenState._defaultWTotal;
      case _MaterialConsumptionScreenState._colLen:
        return _MaterialConsumptionScreenState._defaultWLen;
      case _MaterialConsumptionScreenState._colColor:
        return _MaterialConsumptionScreenState._defaultWColor;
      case _MaterialConsumptionScreenState._colCheck:
        return _MaterialConsumptionScreenState._defaultWCheck;
      default:
        return 100;
    }
  }

  void _resizeColumn(String key, double delta) {
    final current = _columnWidth(key, _defaultColumnWidth(key));
    _tablePreferencesLoadGeneration++;
    _setScreenState(() {
      _tableColumnWidths[key] = (current + delta)
          .clamp(_columnMinWidth(key), _columnMaxWidth(key))
          .toDouble();
    });
    _tableColumnSaveDebounce?.cancel();
    _tableColumnSaveDebounce = Timer(
      const Duration(milliseconds: 250),
      _persistTableColumnLayout,
    );
  }

  void _finishColumnResize() {
    _tableColumnSaveDebounce?.cancel();
    _tableColumnSaveDebounce = null;
    _persistTableColumnLayout();
  }

  Future<SharedPreferences> _getTablePreferences() =>
      _tablePreferencesFuture ??= SharedPreferences.getInstance();

  Future<void> _loadTableColumnLayout() async {
    final loadGeneration = ++_tablePreferencesLoadGeneration;
    try {
      final prefs = await _getTablePreferences();
      final raw = prefs.getString(_MaterialConsumptionScreenState._tableColumnLayoutKey);
      if (raw == null || raw.trim().isEmpty) return;

      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      final rawWidths = decoded['widths'];
      if (rawWidths is! Map) return;

      final loaded = <String, double>{};
      for (final entry in rawWidths.entries) {
        final value = entry.value;
        final width = value is num
            ? value.toDouble()
            : double.tryParse(value?.toString() ?? '');
        if (width != null && width.isFinite) {
          final key = entry.key.toString();
          loaded[key] = width
              .clamp(_columnMinWidth(key), _columnMaxWidth(key))
              .toDouble();
        }
      }
      if (!mounted || loadGeneration != _tablePreferencesLoadGeneration) {
        return;
      }
      _setScreenState(() => _tableColumnWidths.addAll(loaded));
    } catch (error) {
      debugPrint('Material table column layout load failed: $error');
    }
  }

  void _persistTableColumnLayout() {
    final widths = <String, double>{..._tableColumnWidths};
    _tablePersistenceQueue = _tablePersistenceQueue.then((_) async {
      try {
        final prefs = await _getTablePreferences();
        await prefs.setString(
          _MaterialConsumptionScreenState._tableColumnLayoutKey,
          jsonEncode(<String, dynamic>{'widths': widths}),
        );
      } catch (error) {
        debugPrint('Material table column layout save failed: $error');
      }
    });
  }

  // ودجت مساعد صغير: يبني صفًا موحد الشكل (أيقونة + نص + قيمة) لعرض عناصر ملخص التسعير
  Widget _priceRow(
    IconData icon,
    String label,
    String value,
    Color color, {
    bool isBig = false,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Row(
      children: [
        Icon(icon, color: color, size: isBig ? 22 : 18),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: TextStyle(
              fontSize: isBig ? 14 : 12,
              fontWeight: isBig ? FontWeight.bold : FontWeight.normal,
              color: isDark ? Colors.white70 : Colors.black87,
            ),
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: isBig ? 18 : 13,
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    );
  }

  // ==========================================================================
  // دالة: _buildUnifiedTable
  // تبني الجدول الكامل: رأس الجدول + كل الأقسام (بروفيلات/إكسسوارات/ستار/زجاج)
  // مع عناوين الأقسام ومجاميعها، وتضيف عمودًا ثابتًا (overlay) عند التمرير أفقيًا.
  // ==========================================================================
  Widget _buildUnifiedTable(List<BomItem> items) {
    if (items.isEmpty) return const SizedBox.shrink(); // لا يوجد شيء لعرضه
    final isDark = Theme.of(context).brightness == Brightness.dark;
    // دالة داخلية: تحدد هل العنصر "غطاء شفرات" (لأنه يُنقل من قسم accessory إلى قسم shutter في العرض)
    bool isBouchonLame(BomItem i) =>
        i.originalName.contains('أغطية الشفرات') ||
        i.originalName.toLowerCase().contains('bouchons lames') ||
        i.originalName.toLowerCase().contains('bouchon lame');
    // تقسيم كل العناصر إلى مجموعات حسب القسم الذي ستظهر فيه بالجدول
    final Map<String, List<BomItem>> groups = {
      'profile': _orderedMaterialItems(
        'profile',
        items.where((i) => i.category == 'profile').toList(),
      ),
      'accessory': _orderedMaterialItems(
        'accessory',
        items
            .where(
              (i) =>
                  (i.category == 'accessory' && !isBouchonLame(i)) ||
                  (i.category == 'other'),
            )
            .toList(),
      ),
      'joint': _orderedMaterialItems(
        'joint',
        items.where((i) => i.category == 'joint').toList(),
      ),
      // كل مكونات الستار (ما عدا الجوانات) تُعرض معًا في قسم واحد
      'shutter': _orderedMaterialItems(
        'shutter',
        items
            .where(
              (i) =>
                  i.category == 'shutter' ||
                  (i.category == 'accessory' && isBouchonLame(i)),
            )
            .toList(),
      ),
      'glass': _orderedMaterialItems(
        'glass',
        items
            .where((i) => i.category == 'glass' || i.category == 'panneau')
            .toList(),
      ),
      'moustiquaire': _orderedMaterialItems(
        'moustiquaire',
        items.where((i) => i.category == 'moustiquaire').toList(),
      ),
    };
    final totals = _calculateTotals(
      items,
    ); // حساب مجاميع كل قسم لعرضها في عناوين الأقسام
    // Keep one single scrolling table.  The frozen overlay duplicated a slice
    // of the rows above the real table and could become misaligned on phones.
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerSignal: _handleTablePageWheel,
        child: SingleChildScrollView(
          controller:
              _scrollController, // نفس الكونترولر المستخدم لمراقبة موضع التمرير
          scrollDirection:
              Axis.horizontal, // تمرير أفقي لأن الجدول أعرض من الشاشة
          child: SizedBox(
            width: _minW, // عرض ثابت = مجموع عرض كل الأعمدة
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _header(),
                  // صف رأس الجدول (أسماء الأعمدة)
                  // قسم البروفيلات (يظهر فقط إذا كان فيه عناصر)
                  if (groups['profile']!.isNotEmpty) ...[
                    _sectionTitle(
                      'البروفيلات',
                      Colors.blue.shade100,
                      cost: totals['profile']?['cost'],
                      selling: totals['profile']?['selling'],
                    ),
                    ...groups['profile']!.map(_buildDraggableMaterialRow),
                  ],
                  // قسم الإكسسوارات (مقسّم إلى: عناصر كيت مجمّعة + عناصر عادية منفردة)
                  if (groups['accessory']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الإكسسوارات',
                      Colors.orange.shade100,
                      cost: totals['accessory']?['cost'],
                      selling: totals['accessory']?['selling'],
                    ),
                    ..._buildKitGroups(
                      groups['accessory']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    ...groups['accessory']!
                        .where((i) => i.kitGroupName == null)
                        .map(_buildDraggableMaterialRow),
                  ],
                  // قسم مكوّنات الستار (نفس منطق التقسيم: كيت مجمّع + عناصر عادية)
                  if (groups['shutter']!.isNotEmpty) ...[
                    _sectionTitle(
                      'مكوّنات الستار',
                      Colors.purple.shade100,
                      cost: totals['shutter']?['cost'],
                      selling: totals['shutter']?['selling'],
                    ),
                    ..._buildKitGroups(
                      groups['shutter']!
                          .where((i) => i.kitGroupName != null)
                          .toList(),
                    ),
                    ...groups['shutter']!
                        .where((i) => i.kitGroupName == null)
                        .map(_buildDraggableMaterialRow),
                  ],
                  // قسم الموستيكير (Moustiquaire)
                  if (groups['moustiquaire'] != null &&
                      groups['moustiquaire']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الموستيكير',
                      Colors.teal.shade50,
                      cost: totals['moustiquaire']?['cost'],
                      selling: totals['moustiquaire']?['selling'],
                    ),
                    ...groups['moustiquaire']!.map(_buildDraggableMaterialRow),
                  ],
                  // قسم الجوينات (Gaskets)
                  if (groups['joint'] != null &&
                      groups['joint']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الجوينات',
                      Colors.purple.shade50,
                      cost: totals['joint']?['cost'],
                      selling: totals['joint']?['selling'],
                    ),
                    ...groups['joint']!.map(_buildDraggableMaterialRow),
                  ],
                  // قسم الزجاج (بدون كيتات — كل عناصره عادية)
                  if (groups['glass']!.isNotEmpty) ...[
                    _sectionTitle(
                      'الزجاج',
                      Colors.teal.shade100,
                      cost: totals['glass']?['cost'],
                      selling: totals['glass']?['selling'],
                    ),
                    ...groups['glass']!.map(_buildDraggableMaterialRow),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ==========================================================================
  // دالة: _buildMinimalOverlay
  // تبني عمودًا مصغّرًا (يحتوي فقط أسماء الأقسام والعناصر) يظهر ثابتًا على
  // يسار/يمين الشاشة عندما يكون المستخدم قد مرّر الجدول أفقيًا، لتبقى أسماء
  // العناصر مرئية دائمًا أثناء التمرير.
  // ==========================================================================
  // العمود الثابت هو قصّ من الصف الأصلي نفسه، لذلك يبقى بمحاذاة الصف
  // المقابل مهما اختلف ارتفاع النص أو عدد الأسطر.
  Widget _frozenTableSlice(Widget fullRow) {
    return SizedBox(
      width: _frozenWidth,
      child: ClipRect(
        child: OverflowBox(
          alignment: Alignment.topLeft,
          minWidth: _minW,
          maxWidth: _minW,
          child: IgnorePointer(
            child: Directionality(
              textDirection: TextDirection.ltr,
              child: Transform.translate(
                offset: Offset(-_wImg, 0),
                child: SizedBox(width: _minW, child: fullRow),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _buildMinimalKitGroups(List<BomItem> kitItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    if (kitItems.isEmpty) return [];
    final Map<String, List<BomItem>> grouped = {};
    for (final item in kitItems) {
      final group = item.kitGroupName ?? '';
      grouped.putIfAbsent(group, () => []);
      grouped[group]!.add(item);
    }
    final widgets = <Widget>[];
    for (final entry in grouped.entries) {
      final kitName = entry.key;
      final children = entry.value;
      final isExpanded = _kitGroupExpanded[kitName] ?? false;
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت صندوق النفق (Kit Caisson Tunnel)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';
      bool isMatch(String baseName, List<String> aliases) {
        final normalizedKitName = kitName.toLowerCase().replaceAll(
          RegExp(r'[\s_-]'),
          '',
        );
        for (final alias in aliases) {
          final normalizedAlias = alias.toLowerCase().replaceAll(
            RegExp(r'[\s_-]'),
            '',
          );
          if (normalizedKitName == normalizedAlias) return true;
        }
        return false;
      }

      final isDemiOb = isMatch('Demi System OB', [
        'demi system ob',
        'demi_system_ob',
        'system_dim_ob',
        'system dim ob',
        'systemdimob',
        'demisystemob',
        'demisystemeob',
        'systemedimob',
      ]);
      final isSystemOb =
          !isDemiOb &&
          isMatch('System OB', ['system ob', 'system_ob', 'systemob']);
      final isVerrouCentral = isMatch('Verrou Central', [
        'verrou central',
        'verrou_central',
        'vero_central',
        'vero central',
        'verroucentral',
        'verocentral',
      ]);
      final kitItem = children.firstWhere(
        (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );
      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          : (activeVariants[kitItem.originalName] ?? false);
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }
      widgets.add(
        InkWell(
          onTap: () => _setScreenState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
            constraints: const BoxConstraints(minHeight: _MaterialConsumptionScreenState._rowMinHeight),
            width: 140,
            // Match the narrow width
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              border: Border(
                bottom: BorderSide(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                ),
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            alignment: Alignment.centerLeft,
            child: Row(
              children: [
                Icon(
                  isExpanded
                      ? Icons.keyboard_arrow_down
                      : Icons.keyboard_arrow_right,
                  color: isDark ? Colors.purple.shade300 : Colors.grey,
                  size: 16,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    isSystemOb
                        ? 'System OB'
                        : isDemiOb
                        ? 'Demi System OB'
                        : isVerrouCentral
                        ? 'Verrou Central'
                        : kitName,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: isDark
                          ? Colors.purple.shade300
                          : (isGroupActive
                                ? Colors.deepPurple.shade900
                                : Colors.grey),
                      decoration: !isGroupActive
                          ? TextDecoration.lineThrough
                          : null,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      if (isExpanded) {
        final visibleChildren = children
            .where(
              (c) =>
                  !isKitItem(c.originalName) &&
                  c.originalName != 'System OB' &&
                  c.originalName != 'Demi System OB' &&
                  c.originalName != 'Verrou Central',
            )
            .toList();
        widgets.addAll(visibleChildren.map(_minimalRow));
      }
    }
    return widgets;
  }

  Widget _buildMinimalOverlay(Map<String, List<BomItem>> groups) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final totals = _calculateTotals(
      groups.values.expand((group) => group).toList(),
    );

    List<Widget> section(
      String title,
      Color color,
      String key, {
      bool includeKits = false,
    }) {
      final groupItems = groups[key] ?? const <BomItem>[];
      if (groupItems.isEmpty) return const <Widget>[];
      final rows = <Widget>[
        _frozenTableSlice(
          _sectionTitle(
            title,
            color,
            cost: totals[key]?['cost'],
            selling: totals[key]?['selling'],
          ),
        ),
      ];
      if (includeKits) {
        rows.addAll(
          _buildKitGroups(
            groupItems.where((item) => item.kitGroupName != null).toList(),
          ).map(_frozenTableSlice),
        );
      }
      rows.addAll(
        groupItems
            .where((item) => !includeKits || item.kitGroupName == null)
            .map((item) => _frozenTableSlice(_row(item))),
      );
      return rows;
    }

    return Container(
      width: _frozenWidth,
      decoration: BoxDecoration(
        color: isDark
            ? const Color(0xFF161622).withValues(alpha: 0.98)
            : Colors.white.withValues(alpha: 0.98),
        border: Border(
          right: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.35)
                : Colors.grey.shade400,
            width: 2,
          ),
        ),
        boxShadow: const [
          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(2, 0)),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _frozenTableSlice(_header()),
          ...section('البروفيلات', Colors.blue.shade100, 'profile'),
          ...section(
            'الإكسسوارات',
            Colors.orange.shade100,
            'accessory',
            includeKits: true,
          ),
          ...section(
            'مكوّنات الستار',
            Colors.purple.shade100,
            'shutter',
            includeKits: true,
          ),
          ...section('الزجاج', Colors.teal.shade100, 'glass'),
          ...section('الجوينات', Colors.purple.shade50, 'joint'),
        ],
      ),
    );
  }

  // عنوان قسم مصغّر (بدون أرقام التكلفة) للعمود الثابت
  Widget _minimalSectionTitle(String title, Color color) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      height: 35,
      width: double.infinity,
      color: color,
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
      child: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 13,
          color: isDark ? Colors.white70 : Colors.black87,
        ),
      ),
    );
  }

  // صف مصغّر يعرض فقط اسم العنصر (وربما اسمه الفرعي وقائمة القص) في العمود الثابت
  Widget _minimalRow(BomItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isScrews =
        item.name.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');
    return Container(
      constraints: const BoxConstraints(minHeight: _MaterialConsumptionScreenState._rowMinHeight),
      width: 140,
      // Reduced width as requested
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: Text(
        item.kitGroupName != null
            ? Localization.translate(item.name, lang)
            : item.getLocalizedName(_lang),
        maxLines: 3, // Allow up to 3 lines for name if it's long
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.bold,
          color: isScrews
              ? Colors.orange
              : (isDark ? Colors.white70 : Colors.black87),
          decoration: !item.isActive ? TextDecoration.lineThrough : null,
        ),
      ),
    );
  }

  // صف تفصيلي واحد في نافذة "تفاصيل الحساب" — يُخفى تلقائيًا إذا كانت القيمة صفر (وليس صفًا رئيسيًا)
  Widget _detailRow(String label, double price, {bool isBold = false}) {
    if (price == 0 && !isBold) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        textDirection: TextDirection.rtl,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            '${price.toStringAsFixed(2)} دج',
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
              color: isBold ? Colors.green.shade700 : null,
            ),
            textDirection: TextDirection.rtl,
          ),
        ],
      ),
    );
  }

  // رأس الجدول: صف ثابت يحمل عناوين كل الأعمدة (الصورة/البيان/الكمية/سعر الوحدة/التكلفة/الطول/اللون/تفعيل)
  Widget _header() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      color: isDark ? const Color(0xFF1E1E2C) : Colors.blueGrey.shade800,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _headerCell(Localization.translate('الصورة', lang), _MaterialConsumptionScreenState._colImg, _wImg),
            _headerCell(
              Localization.translate('البيان', lang),
              _MaterialConsumptionScreenState._colName,
              _wName,
            ),
            _headerCell(Localization.translate('الكمية', lang), _MaterialConsumptionScreenState._colQty, _wQty),
            _headerCell(
              Localization.translate('الأمتار الفعلية المستعملة', lang),
              _MaterialConsumptionScreenState._colActualMeters,
              _wActualMeters,
            ),
            _headerCell(
              Localization.translate('سعر الوحدة', lang),
              _MaterialConsumptionScreenState._colPrice,
              _wPrice,
            ),
            _headerCell(
              Localization.translate('السعر التقديري', lang),
              _MaterialConsumptionScreenState._colEstimated,
              _wEstimated,
            ),
            _headerCell(
              Localization.translate('التكلفة الفعلية', lang),
              _MaterialConsumptionScreenState._colTotal,
              _wTotal,
            ),
            _headerCell(Localization.translate('الطول', lang), _MaterialConsumptionScreenState._colLen, _wLen),
            _headerCell(
              Localization.translate('اللون', lang),
              _MaterialConsumptionScreenState._colColor,
              _wColor,
            ),
            _headerCell(
              Localization.translate('تفعيل', lang),
              _MaterialConsumptionScreenState._colCheck,
              _wCheck,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }

  Widget _headerCell(
    String title,
    String columnKey,
    double width, {
    bool isLast = false,
  }) {
    const s = TextStyle(
      fontWeight: FontWeight.bold,
      fontSize: 13,
      color: Colors.white,
    );
    return _cell(
      Row(
        children: [
          Expanded(
            child: Text(title, style: s, overflow: TextOverflow.ellipsis),
          ),
          MouseRegion(
            cursor: SystemMouseCursors.resizeColumn,
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onHorizontalDragUpdate: (details) =>
                  _resizeColumn(columnKey, details.delta.dx),
              onHorizontalDragEnd: (_) => _finishColumnResize(),
              onHorizontalDragCancel: _finishColumnResize,
              child: Container(
                width: 14,
                alignment: Alignment.center,
                child: Container(
                  width: 2,
                  height: 24,
                  color: Colors.white.withValues(alpha: 0.35),
                ),
              ),
            ),
          ),
        ],
      ),
      width,
      isLast: isLast,
    );
  }

  // صف عنوان قسم في الجدول (البروفيلات/الإكسسوارات/الستار/الزجاج) مع عرض التكلفة والبيع الاختياريين
  Widget _sectionTitle(
    String title,
    Color color, {
    double? cost,
    double? selling,
  }) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final translatedTitle = Localization.translate(title, lang);
    final currency = Localization.translate('دج', lang);
    return Container(
      color: isDark ? const Color(0xFF25283D) : color,
      width: double.infinity,
      height: 35,
      padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 8),
      child: Row(
        children: [
          Text(
            translatedTitle,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 14,
              color: isDark ? color : Colors.black87,
            ),
          ),
          const SizedBox(width: 12),
          // شارة صغيرة تعرض التكلفة الإجمالية للقسم (تظهر فقط إذا مُررت قيمة cost)
          if (cost != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.white.withValues(alpha: 0.1)
                    : Colors.black.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${Localization.translate('التكلفة:', lang)} ${cost.toStringAsFixed(0)} $currency',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ),
          // شارة صغيرة تعرض سعر البيع الإجمالي للقسم
          if (selling != null)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: isDark
                    ? Colors.green.shade900.withValues(alpha: 0.4)
                    : Colors.green.shade700.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '${Localization.translate('البيع:', lang)} ${selling.toStringAsFixed(0)} $currency',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.green.shade300 : Colors.green.shade800,
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ودجت مساعد عام: يبني خلية جدول واحدة بعرض ثابت وحد فاصل يمين (إلا إذا كانت آخر خلية isLast)
  Widget _cell(
    Widget child,
    double width, {
    bool isLast = false,
    Color? backgroundColor,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      width: width,
      constraints: const BoxConstraints(minHeight: _MaterialConsumptionScreenState._rowMinHeight),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: backgroundColor,
        border: isLast
            ? null
            : BorderDirectional(
                end: BorderSide(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.35)
                      : Colors.grey.shade300,
                ),
              ),
      ),
      alignment: Alignment.centerLeft,
      child: child,
    );
  }

  Widget _row(BomItem item) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final localizedUnit = _localizedBomUnit(item.unit, lang);
    final currency = Localization.translate('دج', lang);
    final inactive = !item.isActive; // العنصر معطّل حاليًا
    final warning =
        item.isMissing &&
        item.isActive &&
        !_bomItemHasResolvedSelection(
          item,
        ); // العنصر مفعّل لكنه "ناقص" (لم يُربط بمكوّن فعلي بعد)
    // تمييز البراغي/الحديد بلون برتقالي مميز
    final isScrews =
        item.originalName.contains('براغي') ||
        item.originalName.contains('حديد') ||
        item.originalName.contains('Renfort') ||
        item.name.contains('حديد') ||
        item.name.contains('Renfort');
    final bool isKitElement =
        item.kitGroupName != null; // هل هذا الصف عنصر فرعي داخل كيت
    final normalizedUnit = item.unit.trim().toLowerCase();
    final isGlassSquareMeter =
        (item.category == 'glass' ||
            item.category == 'panneau' ||
            item.category == 'moustiquaire') &&
        (normalizedUnit == 'م²' ||
            normalizedUnit == 'm²' ||
            normalizedUnit == 'm2' ||
            normalizedUnit == 'sqm');
    String formatQuantity(double value) {
      if ((value - value.roundToDouble()).abs() < 0.000001) {
        return value.round().toString();
      }
      return value.toStringAsFixed(2);
    }

    final quantityLabel = isGlassSquareMeter
        ? '${item.quantity.toStringAsFixed(2)} $localizedUnit'
        : '${formatQuantity(item.quantity)} $localizedUnit';
    final actualRequirement = _actualRequirementFor(item, lang);
    final requirementLines = actualRequirement.split('\n');
    return Container(
      decoration: BoxDecoration(
        color: inactive
            ? (isDark
                  ? Colors.red.shade900.withValues(alpha: 0.3)
                  : Colors.red.shade50) // خلفية حمراء خفيفة للعناصر المعطّلة
            : (isKitElement
                  ? (isDark
                        ? Colors.blue.shade900.withValues(alpha: 0.3)
                        : Colors.blue.shade50.withValues(
                            alpha: 0.5,
                          )) // خلفية زرقاء خفيفة لعناصر الكيت الفرعية
                  : (isDark ? const Color(0xFF1E1E2C) : Colors.white)),
        border: Border(
          bottom: BorderSide(
            color: isDark
                ? Colors.blue.withValues(alpha: 0.15)
                : Colors.grey.shade200,
          ),
        ),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // عمود الصورة: أيقونة مختلفة حسب كون العنصر جزءًا من كيت أو لا
            _cell(
              SectionImageWidget(
                code: item.profileCode,
                name: item.name,
                imagePath: item.imagePath,
                size: isKitElement ? 32.0 : 28.0,
                fallbackIcon: isKitElement ? Icons.extension : Icons.image,
                fallbackColor: isKitElement
                    ? (isDark ? Colors.blue.shade300 : Colors.blue.shade700)
                    : Colors.grey,
              ),
              _wImg,
            ),
            // عمود الاسم: أيقونة تحذير (إن كان ناقصًا) + الاسم + الاسم الثانوي/الكمية + قائمة القص + زر تبديل
            _cell(
              Row(
                children: [
                  if (warning)
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.orange,
                      size: 14,
                    ),
                  if (warning) const SizedBox(width: 4),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          isKitElement
                              ? Localization.translate(
                                  item.name.split('\n').first,
                                  lang,
                                )
                              : item.getLocalizedName(_lang),
                          style: TextStyle(
                            fontSize: isKitElement ? 13.5 : 12,
                            fontWeight: FontWeight.bold,
                            color: isScrews
                                ? Colors.orange
                                : (isKitElement
                                      ? (isDark
                                            ? Colors.blue.shade300
                                            : Colors.blue.shade900)
                                      : (isDark
                                            ? Colors.white70
                                            : Colors.black87)),
                            decoration: inactive
                                ? TextDecoration.lineThrough
                                : null,
                          ),
                        ),
                        if (!isKitElement &&
                            item.catalogItemId != null &&
                            (item.inventoryItemType ?? '').isNotEmpty)
                          Builder(
                            builder: (context) {
                              // Keep stock visibility stable. A missing row
                              // in CurrentStock means available quantity is
                              // zero; it must not make the whole line vanish.
                              final stock = _mainStockFor(item) ?? 0.0;
                              return Text(
                                '${Localization.translate('المستودع الرئيسي', lang)}: ${stock.toStringAsFixed(stock % 1 == 0 ? 0 : 2)} $localizedUnit',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                  color: stock <= 0
                                      ? Colors.red.shade700
                                      : (isDark
                                            ? Colors.teal.shade200
                                            : Colors.teal.shade700),
                                ),
                              );
                            },
                          ),
                        if (isKitElement && item.name.contains('\n'))
                          Text(
                            item.name.split('\n').skip(1).join(' • '),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.normal,
                              color: isDark
                                  ? Colors.grey.shade400
                                  : Colors.grey.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          ),
                        // لعناصر الكيت: عرض الكمية والوحدة تحت الاسم مباشرة
                        if (isKitElement)
                          Text(
                            '${Localization.translate('الكمية:', lang)} ${item.quantity % 1 == 0 ? item.quantity.toInt() : item.quantity} $localizedUnit',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                              color: isDark
                                  ? Colors.blue.shade200
                                  : Colors.blue.shade700,
                              decoration: inactive
                                  ? TextDecoration.lineThrough
                                  : null,
                            ),
                          )
                        // لغير عناصر الكيت: عرض الاسم الأصلي (الثانوي) إن اختلف عن الاسم المترجم
                        else ...[
                          (() {
                            final localizedTitle = item.getLocalizedName(_lang);
                            final parts = item.name.split('\n');
                            final namePart = parts[0];
                            final rawSubparts = parts.length > 1
                                ? parts.sublist(1)
                                : <String>[
                                    if (item.profileCode != null &&
                                        item.profileCode!.trim().isNotEmpty &&
                                        item.profileCode!.trim() != namePart)
                                      item.profileCode!.trim(),
                                  ];
                            final subparts = rawSubparts.where((subText) {
                              final trimmed = subText.trim();
                              if (trimmed.isEmpty) return false;
                              final lower = trimmed.toLowerCase();
                              if (trimmed.contains('المطلوب الفعلي') ||
                                  lower.contains('besoin réel') ||
                                  lower.contains('actual requirement')) {
                                return false;
                              }
                              // Don't show standalone redundant labels that match or repeat part of the title
                              if (lower == 'renforcé' ||
                                  lower == 'renforce' ||
                                  lower == '- renforcé' ||
                                  lower == '- renforce' ||
                                  lower == 'central' ||
                                  lower == 'latéral' ||
                                  lower == 'lateral' ||
                                  lower == 'coulissant' ||
                                  lower == 'dormant') {
                                return false;
                              }
                              if (lower == localizedTitle.toLowerCase())
                                return false;
                              // If French language, hide pure Arabic subparts
                              if (_lang == 'fr' && _hasArabic(trimmed)) {
                                return false;
                              }
                              return true;
                            }).toList();
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (namePart != item.originalName &&
                                    (_lang == 'ar' ||
                                        item.category == 'glass' ||
                                        !_hasArabic(namePart)))
                                  Text(
                                    namePart,
                                    style: TextStyle(
                                      fontSize: item.category == 'glass'
                                          ? 9.0
                                          : 10,
                                      fontWeight: FontWeight.normal,
                                      color: item.category == 'glass'
                                          ? (isDark
                                                ? Colors.grey.shade400
                                                : Colors.grey.shade600)
                                          : (isDark
                                                ? Colors.white54
                                                : Colors.grey.shade700),
                                      decoration: inactive
                                          ? TextDecoration.lineThrough
                                          : null,
                                    ),
                                  ),
                                ...subparts.map(
                                  (subText) => Padding(
                                    padding: const EdgeInsets.only(top: 2.0),
                                    child: Text(
                                      BomItem.localizeSubText(subText, _lang),
                                      style: TextStyle(
                                        fontSize: 9.0,
                                        fontWeight: FontWeight.normal,
                                        color: isDark
                                            ? Colors.grey.shade400
                                            : Colors.grey.shade600,
                                        height: 1.1,
                                        decoration: inactive
                                            ? TextDecoration.lineThrough
                                            : null,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            );
                          })(),
                        ],
                        // قائمة القص (Cutting List) إن وُجدت
                        if (item.cuttingList != null &&
                            item.cuttingList!.isNotEmpty)
                          Padding(
                            padding: const EdgeInsets.only(top: 2.0),
                            child: Text(
                              item.getLocalizedCuttingList(_lang) ??
                                  item.cuttingList!,
                              style: const TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: Colors.blueGrey,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  // زر طريقة قطع الباركلوز (ألمنيوم فقط): 45° أو 90° مع أولوية الطول/العرض
                  if (item.isActive &&
                      (item.selectorType == 'parclose_simple' ||
                          item.selectorType == 'parclose_double') &&
                      ParcloseCutModeSelector.isAvailableFor(widget.model))
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: Tooltip(
                        message: _lang == 'ar'
                            ? 'طريقة قطع الباركلوز'
                            : 'Coupe parclose',
                        child: GestureDetector(
                          onTap: _showParcloseCutModeDialog,
                          child: Icon(
                            Icons.content_cut,
                            color: widget.model.parcloseCutAt90
                                ? Colors.deepPurple
                                : Colors.blueGrey,
                            size: 17,
                          ),
                        ),
                      ),
                    ),
                  // زر التبديل: لعنصر "كيت (Kit)" القديم يظهر قائمة كيت، وإلا أيقونة تبديل عامة تفتح _showSwapDialog
                  if (item.isActive &&
                      item.originalName != 'أغطية الشفرات (Bouchons Lames)')
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: item.originalName == 'كيت (Kit)'
                          ? _buildKitDropdown(item)
                          : GestureDetector(
                              onTap: () => _showSwapDialog(item),
                              child: const Icon(
                                Icons.swap_horiz,
                                color: Colors.orange,
                                size: 18,
                              ),
                            ),
                    ),
                ],
              ),
              _wName,
            ),
            // عمود الكمية
            _cell(
              Text(
                quantityLabel,
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              _wQty,
            ),
            // مجموع أطوال قطع القص الفعلية، وليس عدد القضبان المقرّب.
            _cell(
              Text.rich(
                TextSpan(
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                  children: [
                    TextSpan(
                      text: requirementLines.first,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    if (requirementLines.length > 1)
                      TextSpan(
                        text: '\n${requirementLines.skip(1).join('\n')}',
                        style: const TextStyle(fontWeight: FontWeight.normal),
                      ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              _wActualMeters,
            ),
            // عمود سعر الوحدة + زر تعديل السعر يدويًا (يفتح _showEditPriceDialog)
            _cell(
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '${_isExcludedFromPricing(item) ? 0.0 : item.unitPrice} $currency',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white70 : Colors.black87,
                      ),
                    ),
                  ),
                  if (item.isActive)
                    Padding(
                      padding: const EdgeInsets.only(right: 8.0),
                      child: GestureDetector(
                        onTap: () => _showEditPriceDialog(item),
                        child: const Icon(
                          Icons.edit,
                          color: Colors.blue,
                          size: 16,
                        ),
                      ),
                    ),
                ],
              ),
              _wPrice,
            ),
            // Purchase estimate uses whole stock units; real cost below uses
            // fractional consumption (for example 0.75 bars).
            _cell(
              Text(
                '${(_isExcludedFromPricing(item) || !item.isActive
                    ? 0.0
                    : (item.category == 'glass' || item.category == 'moustiquaire')
                    ? item.total
                    : item.purchaseQuantity * item.unitPrice).toStringAsFixed(2)} $currency',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: isDark ? Colors.white70 : Colors.black87,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              _wEstimated,
            ),
            // مبلغ التكلفة الفعلية: سعر الوحدة × المطلوب الحقيقي.  لا نعرض
            // «المطلوب الحقيقي» ككمية مستقلة لأن هذا العمود للتسعير النقدي.
            _cell(
              Text(
                '${_pricedTotal(item).toStringAsFixed(2)} $currency',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : Colors.black87,
                  decoration: inactive ? TextDecoration.lineThrough : null,
                ),
              ),
              _wTotal,
            ),
            // عمود الطول: للزجاج والموستيكير يعرض "عرض × ارتفاع"، ولغيره الطول بالمتر، وإلا "-"
            _cell(
              Text(
                ((item.category == 'glass' || item.category == 'moustiquaire') && item.glassHeight != null)
                    ? '${item.length?.toStringAsFixed(0)} × ${item.glassHeight?.toStringAsFixed(0)}'
                    : (item.length != null
                          ? '${item.length?.toStringAsFixed(1)}m'
                          : '-'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: (item.category == 'glass' || item.category == 'moustiquaire')
                      ? FontWeight.bold
                      : FontWeight.normal,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
                textAlign: TextAlign.center,
              ),
              _wLen,
            ),
            // عمود اللون (لا يُعرض للزجاج أو الموستيكير)
            _cell(
              Text(
                (item.category == 'glass' || item.category == 'moustiquaire')
                    ? '-'
                    : ((item.category == 'accessory' ||
                                  item.category == 'other') &&
                              (item.colorName ?? '').trim().isEmpty
                          ? ''
                          : localizedColorName(
                              item.colorName ?? '-',
                              Provider.of<AppSettingsProvider>(
                                context,
                                listen: false,
                              ).language,
                            )),
                style: TextStyle(
                  fontSize: 12,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
              _wColor,
            ),
            // عمود التفعيل: Checkbox فقط إذا العنصر تفاعلي (isInteractive)، مع تعطيل خاص لغطاء الشفرات في حالة التونيل
            _cell(
              item.isInteractive
                  ? Checkbox(
                      value: item.isActive,
                      onChanged:
                          (widget.model.isCaissonTunnel &&
                              item.originalName ==
                                  'أغطية الشفرات (Bouchons Lames)')
                          ? null // معطّل تمامًا (إلزامي) في حالة التونيل
                          : (v) => _handleVariantToggle(
                              item.originalName,
                              item.exclusionGroup,
                              v ?? false,
                            ),
                    )
                  : const SizedBox.shrink(),
              // عنصر غير تفاعلي: لا يوجد Checkbox
              _wCheck,
              isLast: true,
            ),
          ],
        ),
      ),
    );
  }
}
