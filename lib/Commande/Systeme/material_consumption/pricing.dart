part of '../material_consumption_screen.dart';

/// Prices, costs and pricing rules of the material table.
extension _MaterialPricing on _MaterialConsumptionScreenState {
  Map<String, dynamic>? _profileCalculationRuleFor(BomItem item) {
    final id = item.catalogItemId;
    return id == null ? null : _profileCalculationRules[id];
  }

  bool _profileUsesLinearMeter(BomItem item) {
    if (_isExcludedFromPricing(item)) return false;
    final mode = _profileCalculationRuleFor(
      item,
    )?['calculation_mode']?.toString().trim().toLowerCase();
    if (mode == 'linear_meter') return true;
    if (mode == 'base_price') return false;
    final role = (item.roleKey ?? item.selectorType ?? '').trim().toLowerCase();
    return role == 'frame' ||
        role == 'frame_extension' ||
        role.startsWith('sash') ||
        role == 'mullion' ||
        role == 'traverse' ||
        role == 'batmo' ||
        role == 'plant';
  }

  bool _isExcludedFromPricing(BomItem item) {
    if (item.category != 'profile') return false;
    final rule = _profileCalculationRuleFor(item);
    return rule?['exclude_from_pricing'] == 1 ||
        rule?['exclude_from_pricing'] == true;
  }

  double _pricedTotal(BomItem item) =>
      _isExcludedFromPricing(item) ? 0.0 : item.total;

  double _profileLinearMultiplier(BomItem item) {
    final rule = _profileCalculationRuleFor(item);
    final mode = rule?['calculation_mode']?.toString().trim().toLowerCase();
    if (mode == 'linear_meter') {
      final value = rule?['linear_meter_multiplier'];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed != null && parsed.isFinite && parsed > 0) return parsed;
    }
    return item.linearMeterMultiplier;
  }

  bool get _isShutterOnlyPricing => widget.model.isShutterOnly;

  /// The kit definition and the kit selling price live in two different
  /// places: KitBundles holds its contents, while ShutterComponents holds the
  /// product named identically with component_type = "kit".  Read the latter
  /// so a kit never inherits the sum/cost of the items inside it.
  Future<double?> _readShutterKitPrice(
    Database database,
    String kitName,
  ) async {
    // Check KitBundles table first (set via PriceManagementScreen)
    final bundleRows = await database.query(
      'KitBundles',
      where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
      whereArgs: [kitName],
      limit: 1,
    );
    if (bundleRows.isNotEmpty) {
      final bPrice = (bundleRows.first['price'] as num?)?.toDouble() ?? 0.0;
      if (bPrice > 0) return bPrice;
    }

    var catalogRows = await database.query(
      'ShutterComponents',
      // ShutterComponents has only the canonical `price` column.  Do not
      // project optional UI fields here: SQLite would fail the whole BOM load
      // when an older database does not contain them.
      columns: const ['id', 'price'],
      where:
          "LOWER(TRIM(name)) = LOWER(TRIM(?)) AND LOWER(TRIM(component_type)) = 'kit' AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [kitName],
      orderBy: 'id DESC',
    );
    if (catalogRows.isEmpty) {
      // KitBundles and ShutterComponents may differ only by punctuation,
      // accents or a trailing unit such as "mm". Match their normalized
      // catalogue names before deciding that the saved official price is 0.
      final allKitRows = await database.query(
        'ShutterComponents',
        columns: const ['id', 'name', 'price'],
        where:
            "LOWER(TRIM(component_type)) = 'kit' AND (is_active = 1 OR is_active IS NULL)",
        orderBy: 'id DESC',
      );
      String normalize(String value) => value
          .toLowerCase()
          .replaceAll(RegExp(r'[^a-z0-9\u0600-\u06ff]+'), ' ')
          .replaceAll(RegExp(r'\bmm\b'), '')
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();

      final wanted = normalize(kitName);
      catalogRows = allKitRows.where((row) {
        final candidate = normalize('${row['name'] ?? ''}');
        return candidate == wanted ||
            (candidate.isNotEmpty &&
                wanted.isNotEmpty &&
                (candidate.contains(wanted) || wanted.contains(candidate)));
      }).toList();
    }
    if (catalogRows.isEmpty) return null;

    final kitProduct = catalogRows.first;
    final componentId = (kitProduct['id'] as num?)?.toInt();
    final colorId = (widget.model.selectedDbColor?['id'] as num?)?.toInt();
    if (componentId != null && colorId != null) {
      final colorRows = await database.query(
        'ShutterColorPrices',
        columns: const ['price'],
        where: 'shutter_component_id = ? AND color_id = ?',
        whereArgs: [componentId, colorId],
        limit: 1,
      );
      if (colorRows.isNotEmpty) {
        final colorPrice = _safeDouble(colorRows.first['price']);
        if (colorPrice > 0) return colorPrice;
      }
    }
    return _safeDouble(kitProduct['price']);
  }

  Future<Map<String, dynamic>> _withShutterKitPrice(
    Database database,
    Map<String, dynamic> kit,
  ) async {
    final pricedKit = Map<String, dynamic>.from(kit);
    final price = await _readShutterKitPrice(
      database,
      pricedKit['name']?.toString() ?? '',
    );
    if (price != null) {
      pricedKit['price'] = price;
      pricedKit['calculated_price'] = price;
    }
    return pricedKit;
  }

  double get _wPrice => _columnWidth(_MaterialConsumptionScreenState._colPrice, _MaterialConsumptionScreenState._defaultWPrice);

  String _priceContextSignature() {
    final model = widget.model;
    final color = model.selectedDbColor?['id']?.toString() ?? '';
    final series =
        model.activeFrameSeries?.id ??
        model.effectiveSlidingSeries?.id ??
        model.activeSeries?.id;
    final bladeOverride = model.componentOverrides['الشرائح (Lames)'];
    final bladeName = bladeOverride?['name']?.toString() ?? model.shutterLame;
    final bladeSubtype = bladeOverride?['shutter_subtype']?.toString() ?? '';
    return '$series|$color|${model.hasShutter}|$bladeName|$bladeSubtype';
  }

  void _scheduleInitialPriceRetries() {
    if (_initialPriceRetryTimers.isNotEmpty) return;
    for (final delay in const [
      Duration(milliseconds: 350),
      Duration(seconds: 1),
      Duration(seconds: 3),
    ]) {
      _initialPriceRetryTimers.add(
        Timer(delay, () {
          if (!mounted) return;
          if (_isFetchingDefaults) return;
          unawaited(_loadPricesFromDb());
        }),
      );
    }
  }

  // ==========================================================================
  // دالة: _loadCostSettings
  // تحميل إعدادات التسعير العامة (نسبة الربح، سعر المتر المربع، معامل العزم،
  // طريقة الحساب) من SharedPreferences، مع قيم افتراضية إن لم تكن محفوظة.
  // ==========================================================================
  Future<void> _loadCostSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _setScreenState(() {
      _profitMargin =
          prefs.getDouble('app_profit_margin') ?? 0.0; // افتراضي 20%
      _pricePerSqm =
          prefs.getDouble('app_price_per_sqm') ?? 0.0; // افتراضي 00 دج/م²
      _torqueFactor =
          prefs.getDouble('shutter_torque_factor') ?? 1.5; // افتراضي 1.5
      // ملاحظة: سعر المتر الخطي يُحمَّل دائمًا من قاعدة البيانات وليس من SharedPreferences
      final methodIndex =
          prefs.getInt('app_cost_method') ?? CostMethod.percentage.index;
      _costMethod =
          CostMethod.values[methodIndex]; // تحويل الرقم المحفوظ إلى enum
      if (_isShutterOnlyPricing && _costMethod == CostMethod.linearMeter) {
        _costMethod = CostMethod.percentage;
      }
      // مزامنة الكونترولرز مع القيم المحمّلة لعرضها في حقول الإدخال
      _profitMarginController.text = _profitMargin.toStringAsFixed(1);
      _pricePerSqmController.text = _pricePerSqm.toStringAsFixed(0);
      _pricePerLinearMeterController.text = '0';
      _torqueFactorController.text = _torqueFactor.toStringAsFixed(1);
    });
  }

  // ==========================================================================
  // دالة: _loadPricesFromDb
  // تحميل الأسعار الديناميكية من قاعدة البيانات: سعر المتر الخطي للسلسلة
  // النشطة، سعر متر مربع الستار (بمطابقة ذكية للاسم/النوع)، وأجور التركيب
  // (صفحة «أجور التركيب»).
  // ==========================================================================
  Future<void> _loadPricesFromDb() async {
    final generation = ++_priceLoadGeneration;
    final dbInstance = await SqlDatabase().db;
    if (dbInstance == null) return;
    final profileRules = <int, Map<String, dynamic>>{};
    try {
      final profileRuleRows = await SqlDatabase().getProfileCalculationRules();
      for (final row in profileRuleRows) {
        final sectionId = (row['section_id'] as num?)?.toInt();
        if (sectionId != null) profileRules[sectionId] = row;
      }
    } catch (e) {
      debugPrint(
        'Error getting profile calculation rules in _loadPricesFromDb: $e',
      );
    }
    final previousLinearMeterPrice = _pricePerLinearMeterFromDb;
    final previousShutterSqmPrice = _shutterSqmPriceFromDb;
    double linearMeterPrice = 0.0;
    double shutterSqmPrice = 0.0;
    final rawColorId = widget.model.selectedDbColor?['id'];
    final colorId = rawColorId is num
        ? rawColorId.toInt()
        : int.tryParse('${rawColorId ?? ''}');
    final seriesId =
        widget.model.activeFrameSeries?.id ??
        widget.model.effectiveSlidingSeries?.id ??
        widget.model.activeSeries?.id;
    // 1. سعر المتر الخطي: أولًا من جدول أسعار السلسلة حسب اللون، وإلا من السعر العام في جدول Series
    if (seriesId != null) {
      if (colorId != null) {
        linearMeterPrice = await SqlDatabase().getSeriesColorPrice(
          seriesId,
          colorId,
        );
      }
      if (linearMeterPrice == 0.0) {
        final seriesRows = await dbInstance.query(
          'Series',
          columns: ['price_per_meter'],
          where: 'id = ?',
          whereArgs: [seriesId],
          limit: 1,
        );
        if (seriesRows.isNotEmpty) {
          linearMeterPrice =
              (seriesRows.first['price_per_meter'] as num?)?.toDouble() ?? 0.0;
        }
      }
      if (linearMeterPrice == 0.0) {
        // Fallback: search SeriesColorPrices for ANY color price for this series.
        // This prevents a temporary/unknown colour id from wiping a valid
        // linear-metre price that is already configured for the series.
        final anyColorRes = await dbInstance.query(
          'SeriesColorPrices',
          where: 'series_id = ? AND price > 0',
          whereArgs: [seriesId],
          limit: 1,
        );
        if (anyColorRes.isNotEmpty) {
          linearMeterPrice =
              (anyColorRes.first['price'] as num?)?.toDouble() ?? 0.0;
        }
      }
    }
    // 2. سعر المتر المربع للستار — يحتاج مطابقة ذكية للاسم لتفادي مشكلة رجوع سعر صفر
    String actualBladeName = ''; // اسم الشريحة الفعلي المستخدم
    String subtype = 'normal'; // نوع الشريحة (extruded/normal)
    final lamesOverride = widget.model.componentOverrides['الشرائح (Lames)'];
    if (lamesOverride != null) {
      actualBladeName = (lamesOverride['name'] ?? '').toString();
      subtype = (lamesOverride['shutter_subtype'] ?? 'normal').toString();
    } else if (widget.model.shutterLame.isNotEmpty) {
      actualBladeName = widget.model.shutterLame;
    }
    if (actualBladeName.isNotEmpty || subtype.isNotEmpty) {
      final allSqmPrices = await dbInstance.query('ShutterSqmPrices');
      shutterSqmPrice = WindowModel.resolveShutterSqmPrice(
        bladeName: actualBladeName,
        bladeSubtype: subtype,
        colorId: colorId,
        prices: allSqmPrices,
      );
      // Prefer the exact blade + selected-colour row over fuzzy matching.
      // Fuzzy matching could pick a generic 730 DZD row when the catalogue
      // contains the explicitly configured 8500 DZD price.
      if (colorId != null) {
        final exactColorRows = await dbInstance.query(
          'ShutterSqmPrices',
          columns: ['price_per_sqm'],
          where:
              'LOWER(TRIM(blade_type)) = ? AND color_id = ? AND price_per_sqm > 0',
          whereArgs: [actualBladeName.trim().toLowerCase(), colorId],
          orderBy: 'id DESC',
          limit: 1,
        );
        if (exactColorRows.isNotEmpty) {
          final exactPrice = _safeDouble(exactColorRows.first['price_per_sqm']);
          if (exactPrice > 0) shutterSqmPrice = exactPrice;
        }
      }
      if (shutterSqmPrice == 0.0) {
        final exactRows = await dbInstance.query(
          'ShutterSqmPrices',
          columns: ['price_per_sqm'],
          where: 'LOWER(TRIM(blade_type)) = ? AND price_per_sqm > 0',
          whereArgs: [actualBladeName.trim().toLowerCase()],
          limit: 1,
        );
        if (exactRows.isNotEmpty) {
          shutterSqmPrice = _safeDouble(exactRows.first['price_per_sqm']);
        }
      }
    }
    // 3. أجور التركيب (صفحة «أجور التركيب»)، منفصلة عن سعر القطع
    final installationFees = await InstallationFees.load(dbInstance);
    // The window colour's own mosquito-net price, else the price of every
    // colour (colour 0).
    final moustiquaireSqmPrice = await SqlDatabase().getShutterSqmPriceForColor(
      'Moustiquaire_Sqm',
      colorId,
    );
    if (!mounted || generation != _priceLoadGeneration) return;
    final effectiveLinearMeterPrice = linearMeterPrice > 0 || seriesId != null
        ? linearMeterPrice
        : previousLinearMeterPrice;
    final effectiveShutterSqmPrice =
        shutterSqmPrice > 0 || actualBladeName.trim().isNotEmpty
        ? shutterSqmPrice
        : previousShutterSqmPrice;
    // تحديث الحالة (State) بكل الأسعار المحمّلة، وتحديث نصوص الحقول إذا لم يكن هناك تعديل يدوي (override)
    _setScreenState(() {
      _profileCalculationRules = profileRules;
      _pricePerLinearMeterFromDb = effectiveLinearMeterPrice;
      _shutterSqmPriceFromDb =
          effectiveShutterSqmPrice; // ⭐️ التحديث الحاسم لسعر الستار
      _moustiquaireSqmPriceFromDb = moustiquaireSqmPrice;
      if (moustiquaireSqmPrice > 0) {
        final existingM = widget.model.componentOverrides['موستيكير (Moustiquaire)'];
        if (existingM is Map) {
          existingM.putIfAbsent('price', () => moustiquaireSqmPrice);
          existingM.putIfAbsent('price_per_sqm', () => moustiquaireSqmPrice);
        } else {
          widget.model.componentOverrides['موستيكير (Moustiquaire)'] = {
            'name': 'موستيكير (Moustiquaire)',
            'price': moustiquaireSqmPrice,
            'price_per_sqm': moustiquaireSqmPrice,
            'calculated_price': moustiquaireSqmPrice,
            'price_dzd': moustiquaireSqmPrice,
          };
        }
        final existingM2 = widget.model.componentOverrides['moustiquaire'];
        if (existingM2 is Map) {
          existingM2.putIfAbsent('price', () => moustiquaireSqmPrice);
          existingM2.putIfAbsent('price_per_sqm', () => moustiquaireSqmPrice);
        } else {
          widget.model.componentOverrides['moustiquaire'] = {
            'name': 'موستيكير (Moustiquaire)',
            'price': moustiquaireSqmPrice,
            'price_per_sqm': moustiquaireSqmPrice,
            'calculated_price': moustiquaireSqmPrice,
            'price_dzd': moustiquaireSqmPrice,
          };
        }
        for (int i = 0; i < _visibleBomItems.length; i++) {
          if (_visibleBomItems[i].category == 'moustiquaire' && _visibleBomItems[i].unitPrice <= 0) {
            _visibleBomItems[i] = _visibleBomItems[i].copyWith(unitPrice: moustiquaireSqmPrice);
          }
        }
      }
      _installationFees = installationFees;
      if (_pricePerLinearMeterOverride == null) {
        _pricePerLinearMeterController.text = effectiveLinearMeterPrice
            .toStringAsFixed(0);
      }
      if (_shutterSqmPriceOverride == null) {
        _shutterSqmPriceController.text = effectiveShutterSqmPrice
            .toStringAsFixed(0);
      }
    });
  }

  // حفظ إعداد تسعير رقمي واحد في SharedPreferences (بالمفتاح المعطى)
  Future<void> _saveCostSetting(String key, double value) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setDouble(key, value);
  }

  // حفظ طريقة الحساب المختارة (percentage/squareMeter/linearMeter) في SharedPreferences
  Future<void> _saveCostMethod(CostMethod method) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('app_cost_method', method.index);
  }

  // ==========================================================================
  // دالة: _buildCostMethodSelector
  // تبني بطاقة (Card) تحوي: اختيار طريقة الحساب، حقل الإدخال الخاص بها،
  // إعداد الكمية، وملخص التسعير النهائي (تكلفة بدون هدر + سعر البيع).
  // ==========================================================================
  Widget _buildCostMethodSelector() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final items = _visibleBomItems
        .where((item) {
          final hasPieces = item.pieces != null && item.pieces!.isNotEmpty;
          final qty = item.requiredQuantity > 0
              ? item.requiredQuantity
              : item.quantity;
          return hasPieces || qty > 0;
        })
        .toList(growable: false);
    final totals = _calculateTotals(items);
    final double totalCostNoWaste =
        totals['total']?['cost'] ?? 0.0; // التكلفة الصافية بدون هدر
    final double sellingPrice = totals['total']?['selling'] ?? 0.0;
    return Card(
      margin: const EdgeInsets.all(16.0),
      elevation: 3,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localization.translate('cost_calculation_method', lang),
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            // أزرار اختيار طريقة الحساب (Chips) — عند الاختيار تُحفظ في SharedPreferences فورًا
            Wrap(
              spacing: 8.0,
              children: CostMethod.values
                  .where(
                    (method) =>
                        !_isShutterOnlyPricing ||
                        method != CostMethod.linearMeter,
                  )
                  .map((method) {
                    final isSelected = _costMethod == method;
                    String label = '';
                    if (method == CostMethod.percentage) {
                      label = Localization.translate('percentage', lang);
                    } else if (method == CostMethod.squareMeter) {
                      label = Localization.translate('square_meter', lang);
                    } else if (method == CostMethod.linearMeter) {
                      label = Localization.translate('linear_meter', lang);
                    }
                    return ChoiceChip(
                      label: Text(label),
                      selected: isSelected,
                      onSelected: (selected) {
                        if (selected) {
                          _setScreenState(() => _costMethod = method);
                          _saveCostMethod(method);
                        }
                      },
                      selectedColor: isDark
                          ? Colors.blue.shade900.withValues(alpha: 0.6)
                          : Colors.blue.shade100,
                      checkmarkColor: isDark
                          ? Colors.blue.shade100
                          : Colors.blue.shade800,
                      labelStyle: TextStyle(
                        color: isSelected
                            ? (isDark
                                  ? Colors.blue.shade100
                                  : Colors.blue.shade900)
                            : (isDark ? Colors.white70 : Colors.black87),
                        fontWeight: isSelected
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    );
                  })
                  .toList(),
            ),
            const SizedBox(height: 16),
            // حقل إدخال مختلف يظهر حسب طريقة الحساب المختارة حاليًا
            if (_costMethod == CostMethod.percentage)
              TextField(
                controller: _profitMarginController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate('نسبة الربح (%)', lang),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.percent),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  _setScreenState(() => _profitMargin = parsed);
                  _saveCostSetting('app_profit_margin', parsed);
                },
              )
            else if (_costMethod == CostMethod.squareMeter &&
                !_isShutterOnlyPricing)
              TextField(
                controller: _pricePerSqmController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    'سعر المتر المربع (دج)',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.aspect_ratio),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val) ?? 0.0;
                  _setScreenState(() => _pricePerSqm = parsed);
                  _saveCostSetting('app_price_per_sqm', parsed);
                },
              )
            else if (_costMethod == CostMethod.linearMeter) ...[
              TextField(
                controller: _pricePerLinearMeterController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    _pricePerLinearMeterOverride == null
                        ? 'سعر المتر الخطي (دج) — من السلسلة'
                        : 'سعر المتر الخطي (دج) — تعديل يدوي',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.linear_scale,
                    color: Colors.blue,
                  ),
                  // زر إلغاء التعديل اليدوي (يرجع للقيمة من قاعدة البيانات) أو زر إعادة تحميل إذا لا يوجد تعديل
                  suffixIcon: _pricePerLinearMeterOverride != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          onPressed: () {
                            _setScreenState(() {
                              _pricePerLinearMeterOverride = null;
                              _pricePerLinearMeterController.text =
                                  _pricePerLinearMeterFromDb.toStringAsFixed(0);
                            });
                          },
                        )
                      : IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.blue),
                          tooltip: Localization.translate(
                            'إعادة تحميل من قاعدة البيانات',
                            lang,
                          ),
                          onPressed: _loadPricesFromDb,
                        ),
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  _setScreenState(() {
                    _pricePerLinearMeterOverride =
                        parsed; // أي تعديل يدوي هنا يتجاوز قيمة القاعدة
                  });
                },
              ),
            ],
            // حقل سعر متر الستار وحقل معامل العزم — يظهران فقط إذا كان في النافذة ستار أصلًا
            if (widget.model.hasShutter) ...[
              const SizedBox(height: 10),
              TextField(
                controller: _shutterSqmPriceController,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: Localization.translate(
                    _shutterSqmPriceOverride == null
                        ? 'سعر المتر المربع للستار (دج) — من الكتالوج'
                        : 'سعر المتر المربع للستار (دج) — تعديل يدوي',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(
                    Icons.view_quilt,
                    color: Colors.purple,
                  ),
                  suffixIcon: _shutterSqmPriceOverride != null
                      ? IconButton(
                          icon: const Icon(Icons.clear, color: Colors.red),
                          onPressed: () {
                            _setScreenState(() {
                              _shutterSqmPriceOverride = null;
                              _shutterSqmPriceController.text =
                                  _shutterSqmPriceFromDb.toStringAsFixed(0);
                            });
                          },
                        )
                      : null,
                ),
                onChanged: (val) {
                  final parsed = double.tryParse(val);
                  _setScreenState(() {
                    _shutterSqmPriceOverride = parsed;
                  });
                },
              ),
              // حقل معامل عزم المحرك — يظهر فقط عند اختيار آلية "محرك"، وتغييره يعيد حساب المحرك المناسب فورًا
              if (widget.model.shutterMechanism == 'محرك') ...[
                const SizedBox(height: 10),
                TextField(
                  controller: _torqueFactorController,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'معامل عزم المحرك (وزن كغ لكل 1 نيوتن) (الافتراضي: 1.6)',
                      lang,
                    ),
                    border: const OutlineInputBorder(),
                    prefixIcon: const Icon(Icons.bolt, color: Colors.orange),
                  ),
                  onChanged: (val) {
                    final parsed = double.tryParse(val) ?? 1.6;
                    _setScreenState(() {
                      _torqueFactor = parsed;
                    });
                    _saveCostSetting('shutter_torque_factor', parsed);
                    _fetchDefaults(); // إعادة اختيار المحرك المناسب فورًا بعد تغيير المعامل
                  },
                ),
              ],
            ],
            if (widget.model.hasMoustiquaireAddon) ...[
              const SizedBox(height: 10),
              InputDecorator(
                decoration: InputDecoration(
                  labelText: Localization.translate(
                      'سعر المتر المربع للموستيكير (دج) — من إدارة الأسعار',
                    lang,
                  ),
                  border: const OutlineInputBorder(),
                  prefixIcon: const Icon(Icons.grid_on_rounded, color: Colors.green),
                ),
                child: Text(
                  '${_moustiquaireSqmPriceFromDb.toStringAsFixed(2)} ${Localization.translate('دج / م²', lang)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 5),
                child: Text(
                  Localization.translate(
                  'المساحة = عرض النافذة × ارتفاعها × الكمية. تعديل السعر يتم من إدارة الأسعار فقط.',
                    lang,
                  ),
                  style: const TextStyle(fontSize: 11, color: Colors.grey),
                ),
              ),
            ],
            const SizedBox(height: 20),
            const Divider(),
            const SizedBox(height: 12),
            // حقل تعديل "الكمية" (عدد النوافذ المتطابقة المطلوبة)
            Row(
              children: [
                const Icon(
                  Icons.format_list_numbered,
                  color: Colors.blue,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Text(
                  Localization.translate('الكمية:', lang),
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    color: isDark ? Colors.white70 : Colors.black87,
                  ),
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 90,
                  child: TextFormField(
                    initialValue: '${widget.model.quantity}',
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        vertical: 8,
                        horizontal: 4,
                      ),
                      isDense: true,
                    ),
                    onChanged: (val) {
                      final parsed = int.tryParse(val);
                      if (parsed != null && parsed > 0) {
                        _updateRequestedQuantity(parsed);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  Localization.translate('نافذة', lang),
                  style: TextStyle(
                    fontSize: 13,
                    color: isDark ? Colors.white54 : Colors.grey,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            // بطاقة ملخص التسعير النهائي (تكلفة بدون هدر / سعر البيع المقترح)
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF1E1E2C) : Colors.grey.shade50,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: isDark
                      ? Colors.blue.withValues(alpha: 0.15)
                      : Colors.grey.shade200,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    Localization.translate('ملخص تسعير', lang),
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isDark ? Colors.white70 : Colors.black54,
                    ),
                  ),
                  const SizedBox(height: 10),
                  _priceRow(
                    Icons.monetization_on_outlined,
                    Localization.translate('سعر التكلفة (بدون هدر)', lang),
                    '${totalCostNoWaste.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.orange.shade700,
                  ),
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),
                  _priceRow(
                    Icons.sell_rounded,
                    Localization.translate('سعر البيع المقترح', lang),
                    '${sellingPrice.toStringAsFixed(0)} ${Localization.translate('دج', lang)}',
                    Colors.green.shade700,
                    isBig: true, // خط أكبر لإبراز السعر النهائي
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // نافذة تعرض تفصيل أسعار البيع لكل قسم (بروفيلات/زجاج/ستار/إكسسوارات) + المجموع
  void _showCalculationDetails(
    double profileSelling,
    double glassSelling,
    double shutterSelling,
    double accessorySelling,
    double moustiquaireSelling,
    double installationSelling,
    double finalSellingPrice,
  ) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate('تفاصيل الحساب', lang),
          textDirection: TextDirection.rtl,
        ),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              _detailRow(
                Localization.translate('سعر البروفيلات:', lang),
                profileSelling,
              ),
              _detailRow(
                Localization.translate('سعر الزجاج:', lang),
                glassSelling,
              ),
              _detailRow(
                Localization.translate('سعر الستار:', lang),
                shutterSelling,
              ),
              _detailRow(
                Localization.translate('سعر الإكسسوارات:', lang),
                accessorySelling,
              ),
              _detailRow(
                Localization.translate('سعر الموستيكير:', lang),
                moustiquaireSelling,
              ),
              _detailRow(
                Localization.translate('أجور التركيب:', lang),
                installationSelling,
              ),
              for (final line in _installationFees.linesFor(
                widget.model,
                _visibleBomItems,
              ))
                _detailRow(
                  '   • ${Localization.translate(line.label, lang)} × ${_formatInstallQuantity(line.quantity)}',
                  line.total,
                ),
              const Divider(thickness: 2),
              _detailRow(
                Localization.translate('المجموع الإجمالي:', lang),
                finalSellingPrice,
                isBold: true,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(Localization.translate('إغلاق', lang)),
          ),
        ],
      ),
    );
  }

  // ==========================================================================
  // دالة: _updatePriceInDatabase
  // تحفظ سعرًا جديدًا "بشكل دائم" في قاعدة البيانات (وليس فقط كـ override
  // مؤقت في هذا الطلب)، مع منطق مختلف لكل فئة (بروفيل/إكسسوار/ستار/جوان/زجاج).
  // ==========================================================================
  Future<void> _updatePriceInDatabase(BomItem item, double newPrice) async {
    final db = await SqlDatabase().db;
    if (db == null) return;
    // البحث عن معرف العنصر في جميع المصادر الممكنة
    Map<String, dynamic>? override = _componentOverrideForBom(item);
    if (override == null) {
      final origLower = item.originalName.toLowerCase();
      if (origLower.contains('إطار') ||
          origLower.contains('frame') ||
          origLower.contains('cadre')) {
        override =
            widget.model.frameOverride ?? widget.model.slidingFrameOverride;
      } else if (origLower.contains('ظلف') ||
          origLower.contains('sash') ||
          origLower.contains('ouvrant')) {
        override =
            widget.model.sashOverride ?? widget.model.slidingSashOverride;
      } else if (origLower.contains('side_cover') ||
          origLower.contains('تغطية') ||
          origLower.contains('الغطاء الجانبي')) {
        override = widget.model.sideCoverOverride;
      }
    }

    // جلب المعرف الحقيقي سواء من catalogItemId أو من الـ override
    int? dbId =
        item.catalogItemId ??
        (override?['id'] is num
            ? (override!['id'] as num).toInt()
            : int.tryParse('${override?['id'] ?? ''}'));

    if (dbId == null && item.category == 'profile') {
      if (item.profileCode != null && item.profileCode!.isNotEmpty) {
        final sec = await db.query('Sections', columns: ['id'], where: 'code = ?', whereArgs: [item.profileCode], limit: 1);
        if (sec.isNotEmpty) dbId = (sec.first['id'] as num).toInt();
      }
      if (dbId == null && item.name.isNotEmpty) {
        final sec = await db.query('Sections', columns: ['id'], where: 'name = ?', whereArgs: [item.name], limit: 1);
        if (sec.isNotEmpty) dbId = (sec.first['id'] as num).toInt();
      }
    }

    // استخراج معرف اللون بدقة من عمود الجدول (item.colorId أو item.colorName) أو من لون النموذج المختار
    int? resolvedColorId = item.colorId;
    if (resolvedColorId == null || resolvedColorId <= 0) {
      if (item.category == 'accessory') {
        resolvedColorId = _selectedAccessoryColorId();
      } else {
        final rawId = widget.model.selectedDbColor?['id'];
        resolvedColorId = rawId is num ? rawId.toInt() : int.tryParse('${rawId ?? ''}');
      }
    }

    // إذا لم يتوفر المعرف بعد، نقوم بمطابقته فوراً بالاسم المكتوب في عمود اللون (item.colorName) أو لون النافذة
    final targetColorName = (item.colorName != null && item.colorName!.trim().isNotEmpty)
        ? item.colorName!.trim()
        : (widget.model.selectedDbColor?['name']?.toString().trim() ??
            widget.model.frameColor.toString().split('.').last.trim());

    if ((resolvedColorId == null || resolvedColorId <= 0) && targetColorName.isNotEmpty && targetColorName != '-') {
      final cRows = await db.query(
        'Colors',
        columns: ['id'],
        where: 'LOWER(TRIM(name)) = LOWER(TRIM(?))',
        whereArgs: [targetColorName],
        limit: 1,
      );
      if (cRows.isNotEmpty) {
        resolvedColorId = (cRows.first['id'] as num).toInt();
      } else {
        // بحث مرن في حال وجود كلمات إضافية مثل Blanc أو الأبيض
        final allColors = await db.query('Colors', columns: ['id', 'name']);
        for (final row in allColors) {
          final cName = (row['name'] ?? '').toString().trim().toLowerCase();
          final tName = targetColorName.toLowerCase();
          if (cName == tName || cName.contains(tName) || tName.contains(cName)) {
            resolvedColorId = (row['id'] as num).toInt();
            break;
          }
        }
      }
    }

    final colorId = resolvedColorId;

    String? errorMsg;
    bool success = false;
    try {
      if (item.category == 'profile') {
        if (dbId != null) {
          if (resolvedColorId != null && resolvedColorId > 0) {
            await SqlDatabase().setSectionColorPrice(dbId, resolvedColorId, newPrice);
          } else {
            // تحديث جميع الأسعار المسجلة مسبقاً لهذا البروفيل في SectionColorPrices
            final existingRows = await db.query(
              'SectionColorPrices',
              columns: ['color_id'],
              where: 'section_id = ?',
              whereArgs: [dbId],
            );
            if (existingRows.isNotEmpty) {
            await db.update(
                'SectionColorPrices',
                {'price': newPrice},
                where: 'section_id = ?',
              whereArgs: [dbId],
            );
            } else {
              // إذا لم تكن هناك أي ألوان مسجلة لهذا البروفيل أصلاً، نربطه باللون الافتراضي (الأبيض) أو أول لون متاح
              final whiteColor = await db.query(
                'Colors',
                columns: ['id'],
                where: "LOWER(name) LIKE '%white%' OR LOWER(name) LIKE '%blanc%' OR name LIKE '%أبيض%' OR name LIKE '%ابيض%'",
                limit: 1,
              );
              int? fallbackColorId = whiteColor.isNotEmpty ? (whiteColor.first['id'] as num).toInt() : null;
              if (fallbackColorId == null) {
                final anyColor = await db.query('Colors', columns: ['id'], limit: 1);
                if (anyColor.isNotEmpty) {
                  fallbackColorId = (anyColor.first['id'] as num).toInt();
                }
              }
              if (fallbackColorId != null) {
                await SqlDatabase().setSectionColorPrice(dbId, fallbackColorId, newPrice);
              }
            }
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'accessory') {
        if (dbId != null) {
          // تحقق: هل هذا الإكسسوار له أسعار لونية مسجّلة أصلًا؟
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM AccessoryColorPrices WHERE accessory_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            // إذا له نظام تسعير لوني، أضف/حدّث سعر هذا اللون تحديدًا
            await db.insert('AccessoryColorPrices', {
              'accessory_id': dbId,
              'color_id': colorId,
              'price': newPrice,
            }, conflictAlgorithm: ConflictAlgorithm.replace);
          } else {
            // وإلا حدّث السعر العام مباشرة في جدول Accessories
            await db.update(
              'Accessories',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'shutter') {
        // نفس منطق الإكسسوارات لكن على جدولي ShutterColorPrices/ShutterComponents
        if (dbId != null) {
          final countRes = await db.rawQuery(
            'SELECT COUNT(*) as count FROM ShutterColorPrices WHERE shutter_component_id = ?',
            [dbId],
          );
          final hasColorPrices = (countRes.first['count'] as int? ?? 0) > 0;
          if (hasColorPrices && colorId != null) {
            await SqlDatabase().setShutterColorForComponent(
              shutterComponentId: dbId,
              colorId: colorId,
              enabled: true,
              price: newPrice,
            );
          } else {
            await db.update(
              'ShutterComponents',
              {'price': newPrice},
              where: 'id = ?',
              whereArgs: [dbId],
            );
          }
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'joint') {
        // الجوانات: تُخزَّن كسعر لكل متر مباشرة (بدون نظام ألوان منفصل)
        if (dbId != null) {
          await db.update(
            'Joints',
            {'price_per_meter': newPrice},
            where: 'id = ?',
            whereArgs: [dbId],
          );
          success = true;
        } else {
          errorMsg = 'العنصر غير مرتبط بقاعدة البيانات';
        }
      } else if (item.category == 'moustiquaire' || item.overrideKey == 'moustiquaire') {
        // Edit the window colour's own price when it has one, else the
        // price of every colour.
        final windowColorId =
            (widget.model.selectedDbColor?['id'] as num?)?.toInt() ?? 0;
        final ownColorPrice = windowColorId > 0
            ? await SqlDatabase().getShutterSqmPrice(
                'Moustiquaire_Sqm',
                windowColorId,
              )
            : 0.0;
        await db.insert('ShutterSqmPrices', {
          'blade_type': 'Moustiquaire_Sqm',
          'color_id': ownColorPrice > 0 ? windowColorId : 0,
          'price_per_sqm': newPrice,
        }, conflictAlgorithm: ConflictAlgorithm.replace);
        _moustiquaireSqmPriceFromDb = newPrice;
        success = true;
      } else if (item.category == 'glass' || item.category == 'panneau') {
        // الزجاج: عملية أكثر تعقيدًا — تحاول إيجاد سجل الزجاج المطابق بالضبط عبر التشطيب واللون
        if (widget.model.zones.isNotEmpty) {
          final glassSpec = widget.model.zones.first.glass;
          if (glassSpec.structure == GlassStructure.simple) {
            // زجاج بسيط (طبقة واحدة): نبحث عن السجل بمطابقة كلمات مفتاحية للتشطيب واللون
            final finishKws = widget.model.getFinishKeywords(
              glassSpec.finishOuter,
            );
            final colorKws = widget.model.getColorKeywords(
              glassSpec.colorOuter,
            );
            final glassList = await db.query('Glass');
            int? matchedGlassId;
            // المحاولة الأولى: تطابق التشطيب واللون معًا
            for (var g in glassList) {
              String t = g['type'].toString().toLowerCase();
              String n = g['name'].toString().toLowerCase();
              String c = (g['color'] ?? '').toString().toLowerCase();
              bool matchesFinish = finishKws.any(
                (kw) => t.contains(kw) || n.contains(kw),
              );
              bool matchesColor = colorKws.any(
                (kw) => kw.isEmpty ? c.isEmpty : (c == kw || c.contains(kw)),
              );
              if (matchesFinish && matchesColor) {
                matchedGlassId = g['id'] as int?;
                break;
              }
            }
            // المحاولة الثانية (بديلة): مطابقة التشطيب فقط إذا فشلت المطابقة الكاملة
            if (matchedGlassId == null) {
              for (var g in glassList) {
                String t = g['type'].toString().toLowerCase();
                String n = g['name'].toString().toLowerCase();
                bool matchesFinish = finishKws.any(
                  (kw) => t.contains(kw) || n.contains(kw),
                );
                if (matchesFinish) {
                  matchedGlassId = g['id'] as int?;
                  break;
                }
              }
            }
            if (matchedGlassId != null) {
              await db.update(
                'Glass',
                {'price_per_sqm': newPrice},
                where: 'id = ?',
                whereArgs: [matchedGlassId],
              );
              success = true;
            } else {
              errorMsg = 'لم يتم العثور على زجاج مطابق في قاعدة البيانات';
            }
          } else {
            // زجاج مزدوج (Double Glazing): لا يمكن تعديل سعره من هنا مباشرة، لأنه مكوّن من عدة أجزاء
            errorMsg =
                'لأن هذا زجاج مزدوج، يرجى تعديل أسعار مكوناته في إدارة الأسعار لتحديث قاعدة البيانات بشكل دائم';
          }
        } else {
          errorMsg = 'لا توجد مواصفات زجاج';
        }
      }
    } catch (e) {
      errorMsg = 'خطأ أثناء التحديث: $e'; // أي خطأ غير متوقع يُلتقط هنا
    }
    if (success) {
      CloudSyncService().notifyCatalogChange();
    }
    // عرض رسالة نجاح أو فشل للمستخدم عبر SnackBar
    if (mounted) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            success
                ? Localization.translate(
                    'تم تحديث السعر بنجاح في قاعدة البيانات',
                    lang,
                  )
                : Localization.translate(errorMsg ?? 'فشل التحديث', lang),
          ),
          backgroundColor: success ? Colors.green : Colors.red,
        ),
      );
    }
  }

  // ==========================================================================
  // دالة: _showEditPriceDialog
  // تفتح نافذة بسيطة لتعديل سعر عنصر واحد، مع خيار "حفظ في قاعدة البيانات
  // أيضًا" (وإلا فالتعديل يبقى محليًا لهذا الطلب فقط عبر componentOverrides).
  // ==========================================================================
  void _showEditPriceDialog(BomItem item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final controller = TextEditingController(text: '${item.unitPrice}');
    bool saveToDb = true; // ✅ تم جعله مفعلاً ومحدداً افتراضياً

    showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            return AlertDialog(
              title: Text(
                '${Localization.translate('تعديل سعر', lang)} ${item.getLocalizedName(_lang)}',
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: controller,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'السعر الجديد (دج)',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                  const SizedBox(height: 12),
                  CheckboxListTile(
                    title: Text(
                      Localization.translate(
                        'حفظ في قاعدة البيانات أيضاً',
                        lang,
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                    value: saveToDb,
                    onChanged: (val) {
                      setStateDialog(() {
                        saveToDb = val ?? true;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  onPressed: () async {
                    final newPrice = double.tryParse(controller.text);
                    if (newPrice != null) {
                      final overrideKey = item.overrideKey ?? item.originalName;
                      final existing =
                          widget.model.componentOverrides[overrideKey] is Map
                          ? Map<String, dynamic>.from(
                              widget.model.componentOverrides[overrideKey],
                            )
                          : <String, dynamic>{};

                      existing['name'] = item.name;
                      existing['price'] = newPrice;
                      existing['calculated_price'] = newPrice;
                      existing['price_dzd'] = newPrice;
                      if (item.catalogItemId != null)
                        existing['id'] = item.catalogItemId;
                      if (item.profileCode != null)
                        existing['code'] = item.profileCode;

                      widget.model.componentOverrides[overrideKey] = existing;
                      // أيضاً نسجل بنفس الاسم الأصلي لضمان التقاط createProfile له
                      widget.model.componentOverrides[item.originalName] =
                          existing;

                      if (item.overrideKey == 'side_cover' ||
                          item.category == 'side_cover' ||
                          item.originalName.contains('الغطاء الجانبي') ||
                          item.selectorType == 'side_cover') {
                        widget.model.sideCoverOverride ??= <String, dynamic>{};
                        widget.model.sideCoverOverride!['price'] = newPrice;
                        widget.model.sideCoverOverride!['calculated_price'] = newPrice;
                        widget.model.sideCoverOverride!['price_dzd'] = newPrice;
                        if (item.catalogItemId != null) widget.model.sideCoverOverride!['id'] = item.catalogItemId;
                        existing['price'] = newPrice;
                        existing['calculated_price'] = newPrice;
                        widget.model.componentOverrides['side_cover'] = existing;
                        widget.model.componentOverrides['الغطاء الجانبي (Side Cover)'] = existing;
                      }
                      if (item.overrideKey == 'sash' || item.originalName.contains('الظلفة') || item.selectorType == 'sash') {
                        widget.model.sashOverride ??= <String, dynamic>{};
                        widget.model.sashOverride!['price'] = newPrice;
                        widget.model.sashOverride!['calculated_price'] = newPrice;
                        widget.model.sashOverride!['price_dzd'] = newPrice;
                        if (item.catalogItemId != null) widget.model.sashOverride!['id'] = item.catalogItemId;
                        widget.model.componentOverrides['sash'] = existing;
                        widget.model.componentOverrides['الظلفة (Sash)'] = existing;
                        for (final z in widget.model.zones) {
                          if (z.sashOverride != null) {
                            z.sashOverride!['price'] = newPrice;
                            z.sashOverride!['calculated_price'] = newPrice;
                            z.sashOverride!['price_dzd'] = newPrice;
                          }
                          if (z.slidingSashOverride != null) {
                            z.slidingSashOverride!['price'] = newPrice;
                            z.slidingSashOverride!['calculated_price'] = newPrice;
                            z.slidingSashOverride!['price_dzd'] = newPrice;
                          }
                        }
                      }
                      if (item.overrideKey == 'frame' || item.originalName.contains('الإطار') || item.selectorType == 'frame') {
                        widget.model.frameOverride ??= <String, dynamic>{};
                        widget.model.frameOverride!['price'] = newPrice;
                        widget.model.frameOverride!['calculated_price'] = newPrice;
                        widget.model.frameOverride!['price_dzd'] = newPrice;
                        if (item.catalogItemId != null) widget.model.frameOverride!['id'] = item.catalogItemId;
                        widget.model.componentOverrides['frame'] = existing;
                        widget.model.componentOverrides['الإطار (Frame)'] = existing;
                      }
                      if (item.overrideKey == 'triangle' || item.originalName.contains('تراينغل') || item.selectorType == 'triangle') {
                        widget.model.componentOverrides['triangle'] = existing;
                        widget.model.componentOverrides['تراينغل الكريمون (Triangle)'] = existing;
                      }
                      if (item.overrideKey == 'moustiquaire' ||
                          item.category == 'moustiquaire' ||
                          item.originalName.contains('موستيكير') ||
                          item.originalName.contains('Moustiquaire')) {
                        existing['price'] = newPrice;
                        existing['price_per_sqm'] = newPrice;
                        existing['calculated_price'] = newPrice;
                        existing['price_dzd'] = newPrice;
                        widget.model.componentOverrides['moustiquaire'] = existing;
                        widget.model.componentOverrides['موستيكير (Moustiquaire)'] = existing;
                        _moustiquaireSqmPriceFromDb = newPrice;
                      }

                      // تحديث فوري للعنصر المعروض في القائمة
                      final itemIdx = _visibleBomItems.indexOf(item);
                      if (itemIdx != -1) {
                        _visibleBomItems = List<BomItem>.from(_visibleBomItems);
                        _visibleBomItems[itemIdx] = item.copyWith(unitPrice: newPrice);
                      }

                      if (saveToDb) {
                        await _updatePriceInDatabase(item, newPrice);
                      }

                      if (mounted) {
                        _setScreenState(() {});
                        await _refreshVisibleBomItems();
                      }
                    }
                    if (dialogContext.mounted) {
                      Navigator.pop(dialogContext);
                    }
                  },
                  child: Text(Localization.translate('حفظ', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }
}
