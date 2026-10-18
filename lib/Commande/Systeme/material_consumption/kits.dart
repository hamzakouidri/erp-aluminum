part of '../material_consumption_screen.dart';

/// Kits and variants of the material table.
extension _MaterialKits on _MaterialConsumptionScreenState {
  bool _isBouchonLameBomItem(BomItem item) =>
      item.originalName.contains('أغطية الشفرات') ||
      item.originalName.toLowerCase().contains('bouchons lames') ||
      item.originalName.toLowerCase().contains('bouchon lame');

  /// Returns true only for bundles that belong to a shutter assembly.  Kit
  /// Bundles also stores window hardware (System OB, Verrou Central, ...),
  /// which must never appear in the shutter-kit selector.
  bool _isShutterKitBundle(Map<String, dynamic> kit) {
    final code = normalizeKitDescriptionCode(kit['description']);
    if (const {'V', 'M', 'MT', 'CT'}.contains(code)) return true;
    if (const {'OB', 'VC'}.contains(code) || code.startsWith('OB')) {
      return false;
    }
    final text = '${kit['name'] ?? ''} ${kit['description'] ?? ''}'
        .toLowerCase();
    final isOtherSystemKit =
        text.contains('system ob') ||
        text.contains('system_ob') ||
        text.contains('demi ob') ||
        text.contains('demi_ob') ||
        text.contains('verrou') ||
        text.contains('central') ||
        text.contains('أوبي') ||
        text.contains('نصف أوبي') ||
        text.contains('فيرو');
    if (isOtherSystemKit) return false;

    return text.contains('kit volet') ||
        text.contains('kit shutter') ||
        text.contains('kit manivelle') ||
        text.contains('kit sangle') ||
        text.contains('كيت فولي') ||
        text.contains('كيت الستار') ||
        text.contains('كيت مانيفال') ||
        text.contains('كيت مانيفر') ||
        text.contains('كيت حزام');
  }

  Future<Map<String, dynamic>?> _findBladeEndCap(
    Map<String, dynamic> blade,
  ) async {
    final database = await SqlDatabase().db;
    if (database == null) return null;
    final bladeName = (blade['name'] ?? '').toString().trim();
    if (bladeName.isEmpty) return null;
    final rows = await database.query(
      'ShutterComponents',
      where:
          "LOWER(TRIM(component_type)) = 'bouchon_lame' AND LOWER(TRIM(shutter_subtype)) = LOWER(TRIM(?)) AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [bladeName],
      orderBy: 'id ASC',
      limit: 1,
    );
    if (rows.isEmpty) return null;
    final result = Map<String, dynamic>.from(rows.first);
    result['calculated_price'] = _safeDouble(
      result['price_dzd'] ?? result['price'],
    );
    return result;
  }

  // ==========================================================================
  // دالة: _findClosestFinalBlade
  // الغرض: إيجاد "الشريحة النهائية" (Final Blade) الأقرب حجمًا لمقاس الشريحة
  // العادية المختارة (targetSize)، ضمن نفس الـ subtype، مع خطة بديلة أوسع.
  // ==========================================================================
  bool _isX3dBlade(Map<String, dynamic>? blade) {
    if (blade == null) return false;
    final text = '${blade['name'] ?? ''} ${blade['shutter_subtype'] ?? ''}'
        .toLowerCase();
    return text.contains('x3d') ||
        text.contains('extrud') ||
        text.contains('إكسترودي') ||
        text.contains('اكسترودي');
  }

  Future<Map<String, dynamic>?> _findClosestFinalBlade(
    Database dbInstance,
    double targetSize,
    String subtype,
  ) async {
    // بحث عن كل الصفوف اللي اسمها يحتوي "final/finale/نهائي" وبنفس الـ subtype
    var finalBlades = await dbInstance.query(
      'ShutterComponents',
      where:
          "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
          "AND shutter_subtype = ? AND (is_active = 1 OR is_active IS NULL)",
      whereArgs: [subtype],
    );
    if (finalBlades.isEmpty) {
      // خطة بديلة: نفس البحث بدون شرط subtype
      finalBlades = await dbInstance.query(
        'ShutterComponents',
        where:
            "(LOWER(name) LIKE '%final%' OR LOWER(name) LIKE '%finale%' OR name LIKE '%نهائي%') "
            "AND (is_active = 1 OR is_active IS NULL)",
      );
    }
    if (finalBlades.isEmpty)
      return null; // لا توجد شريحة نهائية أصلًا في القاعدة
    // دالة داخلية: تستخرج المقاس الرقمي من الصف (measurement أو من الاسم)
    double parseSize(Map<String, dynamic> component) {
      final sizeStr = getComponentSize(component) ?? '';
      return double.tryParse(sizeStr) ?? 0.0;
    }

    Map<String, dynamic>? closest; // أقرب شريحة نهائية للمقاس المطلوب
    double minDiff = double.infinity; // أصغر فرق تم إيجاده حتى الآن
    // المرور على كل الشرائح النهائية المتاحة لإيجاد الأقرب حجمًا
    for (final row in finalBlades) {
      final sz = parseSize(row);
      if (sz > 0) {
        final diff = (sz - targetSize).abs();
        if (diff < minDiff) {
          minDiff = diff;
          closest = row;
        }
      }
    }
    closest ??= finalBlades
        .first; // إذا كل المقاسات كانت 0 أو غير صالحة، خذ أول نتيجة كخيار أخير
    final row = Map<String, dynamic>.from(closest);
    row['calculated_price'] = _safeDouble(row['price_dzd'] ?? row['price']);
    return row;
  }

  // ==========================================================================
  // دالة: _fetchDefaults  ⭐ (الدالة الأهم في الملف)
  // الغرض: عند فتح الشاشة أو تغيير أي إعداد، تقوم "بالجلب الذكي" لكل المكونات
  // الافتراضية المرتبطة (حديد الدعم، البراغي، الأقفال، الكيتات، المحرك المناسب
  // حسب الوزن...)، وتضبط activeVariants حسب آلية الستار (محرك/مانيفيل/حزام)
  // وحالة الصندوق (تونيل أو لا).
  // ==========================================================================
  void _refreshStrictActiveVariants() {
    final isTunnel = widget.model.isCaissonTunnel;
    final isMotor = widget.model.shutterMechanism == 'محرك';
    activeVariants.addAll(
      ComponentCalculator.standardActiveVariants(widget.model),
    );

    if (!isMotor) {
      widget.model.componentOverrides.remove('الامبو (Embout)');
      widget.model.componentOverrides.remove('سيبور رولمو (Support Roulement)');
      widget.model.componentOverrides.remove('المحرك (Moteur)');
      widget.model.componentOverrides.remove('براغي المحرك');
    }
    if (!isTunnel) {
      widget.model.componentOverrides.remove('طانديم (Tandem)');
    }
    if (!isMotor && !isTunnel) {
      widget.model.componentOverrides.remove('سيبور موتور (Support Moteur)');
    }
  }

  Future<void> _loadStrictKitBundles(
    Database dbInstance,
    SqlDatabase sqlDb,
  ) async {
    final kits = await sqlDb.readKitBundles();
    final bundleData = <String, List<Map<String, dynamic>>>{};
    final perLeafMap = <String, bool>{};
    final metadata = <String, Map<String, dynamic>>{};
    final prices = <String, double>{};

    // Kit definitions are independent. Loading them one after another made
    // every kit wait for all of its child/range queries before the table could
    // be shown.
    final loadedKits = await Future.wait(
      kits.map((kit) async {
        final kitName = kit['name']?.toString() ?? '';
        final kitId = (kit['id'] as num?)?.toInt();
        if (kitName.isEmpty || kitId == null) return null;

        final detailsFuture = sqlDb.readKitBundleItemsWithDetails(
          kitId,
          topLevelOnly: true,
        );
        final priceFuture = _isShutterKitBundle(kit)
            ? _readShutterKitPrice(dbInstance, kitName)
            : Future<double?>.value(null);
        final details = await detailsFuture;
        final price = await priceFuture;
        return (
          name: kitName,
          details: details,
          perLeaf: (kit['per_leaf'] ?? 0) == 1,
          metadata: Map<String, dynamic>.from(kit),
          price: price,
        );
      }),
    );
    for (final loaded in loadedKits) {
      if (loaded == null) continue;
      bundleData[loaded.name] = loaded.details
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
      perLeafMap[loaded.name] = loaded.perLeaf;
      metadata[loaded.name] = loaded.metadata;
      if (loaded.price != null) prices[loaded.name] = loaded.price!;
    }

    _kitBundleData = bundleData;
    _kitPerLeafMap = perLeafMap;
    _kitBundleMetadata = metadata;
    _kitBundlePrices = prices;
  }

  // ==========================================================================
  // دالة: _handleKitSelection
  // تُستدعى عند اختيار المستخدم كيتًا مختلفًا يدويًا من القائمة المنسدلة.
  // تحدد نوع الآلية (محرك/مانيفيل/حزام) من اسم الكيت المختار، وتحدّث النموذج
  // والـ overrides بما يتوافق مع الكيت الجديد.
  // ==========================================================================
  Future<void> _handleKitSelection(Map<String, dynamic> selectedKit) async {
    final mutableSelected = Map<String, dynamic>.from(selectedKit);
    mutableSelected['catalog_source'] = 'KitBundles';
    final calculatedPrice = _safeDouble(mutableSelected['calculated_price']);
    final listedPrice = _safeDouble(mutableSelected['price']);
    final databasePrice = _safeDouble(mutableSelected['price_dzd']);
    mutableSelected['calculated_price'] = calculatedPrice > 0
        ? calculatedPrice
        : (listedPrice > 0 ? listedPrice : databasePrice);
    final selectedName = (mutableSelected['name'] ?? '')
        .toString()
        .toLowerCase();
    final selectedCode = normalizeKitDescriptionCode(
      mutableSelected['description'],
    );
    // Check if it is a sliding system kit
    final bool isSliding = widget.model.systemMode == 'sliding';
    if (isSliding) {
      String targetKey = 'كيت 67000 (Kit 67000)';
      if (selectedName.contains('40000')) {
        targetKey = 'كيت 40000 (Kit 40000)';
      } else if (selectedName.contains('67000')) {
        targetKey = 'كيت 67000 (Kit 67000)';
      } else {
        final String sName =
            widget.model.activeSlidingSeries?.name.toLowerCase() ?? '';
        if (sName.contains('40000')) {
          targetKey = 'كيت 40000 (Kit 40000)';
        } else {
          targetKey = 'كيت 67000 (Kit 67000)';
        }
      }
      final slidingKeys = ['كيت 67000 (Kit 67000)', 'كيت 40000 (Kit 40000)'];
      for (final k in slidingKeys) {
        widget.model.componentOverrides.remove(k);
      }
      widget.model.componentOverrides[targetKey] = mutableSelected;
      await _fetchDefaults();
      if (mounted) {
        _setScreenState(() {
          widget.model.refreshUI();
        });
      }
      return;
    }
    String newMech; // الآلية الجديدة المستنتجة من اسم الكيت
    String
    targetKitKey; // المفتاح الصحيح لحفظ هذا الكيت تحته في componentOverrides
    // استنتاج نوع الآلية من اسم الكيت (محرك/مانيفيل مع فولي أو بدون/حزام)
    if (selectedCode == 'MT') {
      newMech = 'محرك';
      targetKitKey = 'كيت فولي موتور (Kit Volet Moteur)';
    } else if (selectedCode == 'V') {
      final isCurrentCrank =
          widget.model.shutterMechanism == 'منايفال' ||
          widget.model.shutterMechanism == 'مانيفال' ||
          widget.model.shutterMechanism == 'مانيفر';
      newMech = isCurrentCrank ? 'مانيفال' : 'حزام';
      targetKitKey = isCurrentCrank
          ? 'كيت فولي مانيفر (Kit Volet Manivelle)'
          : 'كيت فولي (Kit Volet)';
    } else {
      // Legacy records without a description code keep their old name-based
      // behaviour. Coded records never rely on commercial names.
      if (selectedName.contains('moteur') || selectedName.contains('محرك')) {
        newMech = 'محرك';
        targetKitKey = 'كيت فولي موتور (Kit Volet Moteur)';
      } else if (selectedName.contains('manivelle') ||
          selectedName.contains('مانيفال') ||
          selectedName.contains('مانيفر')) {
        newMech = 'مانيفال';
        targetKitKey =
            selectedName.contains('volet') || selectedName.contains('فولي')
            ? 'كيت فولي مانيفر (Kit Volet Manivelle)'
            : 'كيت مانيفر (Kit Manivelle)';
      } else {
        newMech = 'حزام';
        targetKitKey =
            selectedName.contains('sangle') || selectedName.contains('حزام')
            ? 'كيت حزام (Kit Sangle)'
            : 'كيت فولي (Kit Volet)';
      }
    }
    // تحديث آلية الستار في النموذج
    widget.model.shutterMechanism = newMech;
    // مسح كل الكيتات القديمة من الـ overrides (لتفادي بقاء كيت قديم متضارب)
    final kitKeys = [
      'كيت (Kit)',
      'كيت فولي موتور (Kit Volet Moteur)',
      'كيت فولي مانيفر (Kit Volet Manivelle)',
      'كيت مانيفر (Kit Manivelle)',
      'كيت فولي (Kit Volet)',
      'كيت حزام (Kit Sangle)',
    ];
    for (final k in kitKeys) {
      widget.model.componentOverrides.remove(k);
    }
    // حفظ الكيت المختار تحت المفتاح الصحيح الجديد
    widget.model.componentOverrides[targetKitKey] = mutableSelected;
    final selectedKitSize = kitBundleSizeMm(mutableSelected);
    if (selectedKitSize != null && selectedKitSize > 0) {
      final dbInstance = await SqlDatabase().db;
      if (dbInstance != null) {
        final boxes = await dbInstance.query(
          'ShutterComponents',
          where:
              "(LOWER(name) LIKE '%box%' OR name LIKE '%صندوق%' OR LOWER(name) LIKE '%caisson%' OR LOWER(component_type) IN ('box', 'caisson')) AND (is_active = 1 OR is_active IS NULL)",
        );
        for (final row in boxes) {
          final boxSize = double.tryParse(getComponentSize(row) ?? '');
          if (boxSize != null && (boxSize - selectedKitSize).abs() <= 0.5) {
            final companionBox = Map<String, dynamic>.from(row);
            companionBox['calculated_price'] = _safeDouble(
              companionBox['price_dzd'] ?? companionBox['price'],
            );
            companionBox['manual_override'] = true;
            widget.model.componentOverrides['الصندوق (Caisson)'] = companionBox;
            widget.model.setManualShutterBoxHeight(selectedKitSize);
            break;
          }
        }
      }
    }
    // إعادة حساب الافتراضيات (لأن تغيير الآلية يؤثر على مكونات أخرى كثيرة) وتحديث الواجهة
    await widget.model.updateShutterDefaultsIfNeeded();
    await _fetchDefaults();
    if (mounted) {
      _setScreenState(() {
        widget.model.refreshUI();
      });
    }
  }

  // ==========================================================================
  // دالة: _handleVariantToggle
  // تُستدعى عند تفعيل/تعطيل أي Checkbox لعنصر اختياري (كيت، سيبور، طانديم...).
  // تحتوي منطق "استبعاد متبادل" بين المجموعات (مثلاً تفعيل الطانديم يعطّل
  // الكيتات والامبو تلقائيًا لأنها غير متوافقة معه).
  // ==========================================================================
  void _handleVariantToggle(String name, String? group, bool value) {
    _setScreenState(() {
      activeVariants[name] = value; // تحديث الحالة الأساسية أولًا
      if (name == 'أغطية الشفرات (Bouchons Lames)') {
        const capKey = 'أغطية الشفرات (Bouchons Lames)';
        if (value) {
          final savedCap = _disabledBladeEndCap;
          if (savedCap != null) {
            widget.model.componentOverrides[capKey] = Map<String, dynamic>.from(
              savedCap,
            );
            _disabledBladeEndCap = null;
          }
        } else {
          final currentCap = widget.model.componentOverrides[capKey];
          if (currentCap is Map) {
            _disabledBladeEndCap = Map<String, dynamic>.from(currentCap);
          }
          widget.model.componentOverrides.remove(capKey);
        }
        // Do not let the generic exclusion logic below alter this explicit
        // toggle.  The BOM refresh will recalculate blade lengths from the
        // updated override state.
        widget.model.refreshUI();
        return;
      }
      // تحقق: هل الاسم هو أحد مفاتيح الكيتات؟
      final isAnyKitKey =
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';
      if (name == 'Verrou Central') {
        if (value && !widget.model.canUseOpeningOnlyOptions) {
          activeVariants[name] = false;
          return;
        }
        widget.model.toggleVerrouCentral(
          value,
        ); // تفويض المنطق لدالة النموذج نفسه
      } else if (name == 'System OB') {
        if (value && !widget.model.canUseOpeningOnlyOptions) {
          activeVariants[name] = false;
          return;
        }
        widget.model.toggleSystemOB(value);
      } else if (name == 'Demi System OB') {
        if (!widget.model.canUseDemiOB) {
          activeVariants[name] = false;
          return;
        }
        widget.model.toggleDemiOB(value);
      } else if (isAnyKitKey) {
        // تفعيل أي كيت يعطّل تلقائيًا: الامبو، سيبور رولمو، سيبور موتور، الطانديم (غير متوافقين)
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['سيبور موتور (Support Moteur)'] = false;
          activeVariants['طانديم (Tandem)'] = false;
        }
      } else if (name == 'طانديم (Tandem)') {
        // تفعيل الطانديم يعطّل الامبو والسيبور رولمو وكل الكيتات
        if (value) {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      } else if (name == 'الامبو (Embout)' ||
          name == 'سيبور رولمو (Support Roulement)') {
        // الامبو وسيبور رولمو مرتبطان: تفعيل أحدهما يفعّل الآخر تلقائيًا ويعطّل الطانديم وكل الكيتات
        if (value) {
          activeVariants['الامبو (Embout)'] = true;
          activeVariants['سيبور رولمو (Support Roulement)'] = true;
          activeVariants['طانديم (Tandem)'] = false;
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        } else {
          activeVariants['الامبو (Embout)'] = false;
          activeVariants['سيبور رولمو (Support Roulement)'] = false;
        }
      } else if (name == 'سيبور موتور (Support Moteur)') {
        // تفعيل سيبور موتور يعطّل كل الكيتات
        if (value) {
          activeVariants['كيت (Kit)'] = false;
          activeVariants['كيت فولي موتور (Kit Volet Moteur)'] = false;
          activeVariants['كيت فولي مانيفر (Kit Volet Manivelle)'] = false;
          activeVariants['كيت مانيفر (Kit Manivelle)'] = false;
          activeVariants['كيت حزام (Kit Sangle)'] = false;
          activeVariants['كيت فولي (Kit Volet)'] = false;
        }
      }
      // مزامنة نهائية: إعادة قراءة الحالة الفعلية من النموذج (احتياطًا لأي تعارض)
      activeVariants['Verrou Central'] =
          widget.model.canUseOpeningOnlyOptions &&
          widget.model.useVerrouCentral;
      activeVariants['System OB'] = widget.model.effectiveUseSystemOB;
      activeVariants['Demi System OB'] = widget.model.effectiveUseDemiOB;
      _rememberVariantChoices();
    });
    unawaited(_refreshVisibleBomItems());
  }

  /// Stores the switches that differ from the rules on the drawing, so the
  /// cutting sheet, required goods and a reopened table use the same parts.
  void _rememberVariantChoices() {
    final rules = ComponentCalculator.standardActiveVariants(
      widget.model,
      includeUserChoices: false,
    );
    widget.model.shutterVariantChoices = {
      for (final entry in activeVariants.entries)
        if (!ComponentCalculator.modelBackedVariantKeys.contains(entry.key) &&
            rules.containsKey(entry.key) &&
            rules[entry.key] != entry.value)
          entry.key: entry.value,
    };
    widget.model.shutterVariantChoicesContext =
        ComponentCalculator.shutterVariantContext(widget.model);
  }

  // ==========================================================================
  // دالة: _buildKitDropdown
  // تبني قائمة منسدلة (PopupMenu) لترقية/تغيير كيت الستار الحالي، مع تطبيق
  // قاعدة "الترقية فقط" (لا يمكن اختيار كيت أصغر من الحد الأدنى المسموح
  // حسب ارتفاع النافذة أو حسب الكيت الحالي نفسه إن كان أكبر من الحد).
  // ==========================================================================
  Widget _buildKitDropdown(BomItem item) {
    return FutureBuilder<List<Map<String, dynamic>>>(
      future: () async {
        // The kit selector reads only from the Kits page.  A shutter
        // component with "kit" in its name is never a selectable bundle.
        final dbInstance = await SqlDatabase().db;
        if (dbInstance == null) return <Map<String, dynamic>>[];
        final rows = await dbInstance.query(
          'KitBundles',
          where: 'is_active = 1 OR is_active IS NULL',
        );
        double minimumRequiredSize = widget.model.height <= 1600
            ? 155
            : widget.model.height <= 2400
            ? 185
            : 205;
        final bladeId =
            widget.model.componentOverrides['الشرائح (Lames)']?['id'];
        if (bladeId != null) {
          final limits = await dbInstance.query(
            'ShutterBoxLimits',
            where: 'blade_id = ?',
            whereArgs: [bladeId],
            orderBy: 'box_size ASC',
          );
          final resolution = WindowModel.resolveShutterBoxFromLimits(
            windowHeight: widget.model.height,
            limits: limits,
          );
          if (resolution != null) {
            minimumRequiredSize = resolution.boxSize;
          }
        }
        final shutterKits = rows
            .map((r) => Map<String, dynamic>.from(r))
            .where(_isShutterKitBundle);
        final pricedKits = await Future.wait(
          shutterKits.map((kit) => _withShutterKitPrice(dbInstance, kit)),
        );
        return pricedKits
            .map(
              (kit) => <String, dynamic>{
                ...kit,
                'component_type': 'kit',
                'measurement': extractSizeDigits(kit['name'].toString()),
                'catalog_source': 'KitBundles',
                'minimum_required_size': minimumRequiredSize,
              },
            )
            .toList();
      }(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          // أثناء التحميل: مؤشر دوران صغير بدل الأيقونة
          return const SizedBox(
            width: 20,
            height: 20,
            child: CircularProgressIndicator(strokeWidth: 2),
          );
        }
        final allKits = snapshot.data!;
        final requiredCode = shutterKitCodeForMechanism(
          widget.model.shutterMechanism,
        );
        // The minimum comes from ShutterBoxLimits without treating a larger
        // manual choice as a new minimum. Thus a 155 drawing always offers
        // 155/185/205, while a 185 drawing offers 185/205.
        final minAllowedSize = allKits.isEmpty
            ? widget.model.shutterBoxHeight
            : (allKits.first['minimum_required_size'] as num?)?.toDouble() ??
                  widget.model.shutterBoxHeight;
        final currentKit = widget.model.componentOverrides[item.originalName];
        // عرض المقاس المناسب وكل المقاسات الأكبر فقط.
        final allowedKits = compatibleKitBundles(
          kits: allKits,
          descriptionCode: requiredCode,
          minimumSizeMm: minAllowedSize,
        );
        final currentKitId = currentKit?['id'];
        // بناء قائمة منسدلة (Popup Menu) مع علامة ✓ أمام الكيت الحالي
        return PopupMenuButton<Map<String, dynamic>>(
          icon: const Icon(
            Icons.arrow_drop_down_circle_outlined,
            color: Colors.blue,
            size: 20,
          ),
          tooltip: Localization.translate(
            'تغيير كيت الستار (المناسب ثم الأكبر)',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          onSelected: (selectedKit) async {
            await _handleKitSelection(
              selectedKit,
            ); // تفويض المعالجة الفعلية لدالة _handleKitSelection
          },
          itemBuilder: (context) {
            return allowedKits.map((k) {
              final isCurrent = currentKitId == k['id'];
              return PopupMenuItem<Map<String, dynamic>>(
                value: k,
                child: Row(
                  children: [
                    if (isCurrent)
                      const Icon(Icons.check, color: Colors.green, size: 16)
                    else
                      const SizedBox(width: 16),
                    const SizedBox(width: 8),
                    Text(
                      '${k['name']} (${k['price']} دج)',
                      style: TextStyle(
                        fontWeight: isCurrent
                            ? FontWeight.bold
                            : FontWeight.normal,
                      ),
                    ),
                  ],
                ),
              );
            }).toList();
          },
        );
      },
    );
  }

  // ==========================================================================
  // دالة: _buildKitGroups
  // تبني صفوف الجدول الخاصة بمجموعات الكيت (قابلة للطي/التوسعة)، حيث يظهر
  // رأس المجموعة كصف واحد قابل للنقر، وعناصره الفرعية تظهر فقط عند التوسعة.
  // ==========================================================================
  List<Widget> _buildKitGroups(List<BomItem> kitItems) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    if (kitItems.isEmpty) return []; // لا شيء لعرضه
    // تجميع العناصر حسب اسم مجموعة الكيت (kitGroupName)
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
      final isExpanded =
          _kitGroupExpanded[kitName] ?? false; // حالة الطي/التوسعة الحالية
      final childTotalPrice = children.fold<double>(
        0,
        (sum, i) => sum + _pricedTotal(i),
      );
      final officialKitUnitPrice = _kitBundlePrices[kitName] ?? 0.0;
      // دالة داخلية: تحدد هل عنصر معين هو "رأس كيت" (وليس عنصرًا فرعيًا داخله)
      bool isKitItem(String name) =>
          name == 'كيت (Kit)' ||
          name == 'كيت فولي موتور (Kit Volet Moteur)' ||
          name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
          name == 'كيت مانيفر (Kit Manivelle)' ||
          name == 'كيت صندوق النفق (Kit Caisson Tunnel)' ||
          name == 'كيت حزام (Kit Sangle)' ||
          name == 'كيت فولي (Kit Volet)';
      // عدد العناصر المرئية الفعلية داخل المجموعة (باستثناء رأس الكيت وعناصر OB/Verrou الخاصة)
      final visibleCount = children
          .where(
            (c) =>
                !isKitItem(c.originalName) &&
                c.originalName != 'System OB' &&
                c.originalName != 'Demi System OB' &&
                c.originalName != 'Verrou Central',
          )
          .length;
      // دالة داخلية: تطابق مرن لاسم المجموعة مع مجموعة من الأسماء البديلة (aliases) بعد تطبيع النص
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
          if (normalizedKitName == normalizedAlias) {
            return true;
          }
        }
        return false;
      }

      // تحديد نوع هذه المجموعة تحديدًا (Demi OB / System OB / Verrou Central / كيت ستار عادي)
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
      final isShutterKit = !isSystemOb && !isDemiOb && !isVerrouCentral;
      final shutterKitCode = normalizeKitDescriptionCode(
        _kitBundleMetadata[kitName]?['description'],
      );
      final isResizableShutterKit = const {'V', 'MT'}.contains(shutterKitCode);
      // العنصر الذي يمثل "رأس" هذه المجموعة (أول رأس كيت موجود، أو أول عنصر كخطة بديلة)
      final kitItem = children.firstWhere(
        (c) => isKitItem(c.originalName),
        orElse: () => children.first,
      );
      final kitQuantity = math.max(1, widget.model.quantity).toDouble();
      final isMotorKit =
          shutterKitCode == 'MT' ||
          isMatch('كيت فولي موتور (Kit Volet Moteur)', [
            'kit volet moteur',
            'kit_volet_moteur',
            'kitvoletmoteur',
            'moteur',
          ]) ||
          kitName.toLowerCase().contains('moteur');
      // إذا كان كيت موتور (أو كيت مفصول/معدل) نجمع أسعار العناصر المتبقية بداخله.
      // أما إذا كان كيت عادي كامل (مثل kit volant 155/185/205) وسعره الإجمالي مدخل > 0 نأخذ سعره،
      // وإن كان صفرًا نرجع لمجموع عناصره.
      // القاعدة: إذا وجد سعر للـ Kit (سواء حزام أو موتور أو مانيفر) نعتمد سعر الـ Kit
      // إذا لم يوجد سعر للـ Kit (سعره 0) نعتمد مجموع أسعار عناصره وقطعه الفردية
      final double totalPrice = officialKitUnitPrice > 0
          ? (officialKitUnitPrice * kitQuantity)
          : childTotalPrice;

      final double effectiveKitUnitPrice = officialKitUnitPrice > 0
          ? officialKitUnitPrice
          : (kitQuantity > 0
                ? childTotalPrice / kitQuantity
                : 0.0); // هل المجموعة مفعّلة حاليًا؟ (تُحدد من activeVariants حسب نوعها)
      final isGroupActive = isSystemOb
          ? (activeVariants['System OB'] ?? false)
          : isDemiOb
          ? (activeVariants['Demi System OB'] ?? false)
          : isVerrouCentral
          ? (activeVariants['Verrou Central'] ?? false)
          // A shutter kit is always active when it is present.  It comes
          // from KitBundles rather than the variants map, so a missing map
          // entry must not hide its change button.
          : (activeVariants[kitItem.originalName] ?? kitItem.isActive);
      // إخفاء المجموعة كليًا (بدون عرضها حتى كصف مطفأ) إذا كانت من النوع الخاص (OB/Demi/Verrou) وغير مفعّلة
      if (!isGroupActive && (isSystemOb || isDemiOb || isVerrouCentral)) {
        continue;
      }
      dynamic selectedKit = isShutterKit
          ? widget.model.componentOverrides[kitItem.originalName]
          : null;
      if (selectedKit == null && isShutterKit) {
        final seriesMatch = RegExp(r'40\s*000|67\s*000').firstMatch(kitName);
        final series = seriesMatch?.group(0)?.replaceAll(RegExp(r'\s'), '');
        for (final entry in widget.model.componentOverrides.entries) {
          final keyMatch = RegExp(r'40\s*000|67\s*000').firstMatch(entry.key);
          if (series != null &&
              keyMatch?.group(0)?.replaceAll(RegExp(r'\s'), '') == series) {
            selectedKit = entry.value;
            break;
          }
        }
      }
      final selectedKitName = selectedKit?['name']?.toString();
      // ---- بناء صف "رأس" المجموعة القابل للنقر لفتح/طي العناصر الفرعية ----
      widgets.add(
        InkWell(
          onTap: () => _setScreenState(() => _kitGroupExpanded[kitName] = !isExpanded),
          child: Container(
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
            child: IntrinsicHeight(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // عمود الصورة: أيقونة صندوق عامة تمثل "كيت"
                  _cell(
                    Container(
                      height: 28,
                      color: isDark
                          ? Colors.grey.shade800
                          : Colors.grey.shade200,
                      child: Icon(
                        Icons.inventory_2_outlined,
                        color: isDark ? Colors.white54 : Colors.grey,
                        size: 16,
                      ),
                    ),
                    _wImg,
                  ),
                  // عمود الاسم: سهم توسعة/طي + اسم الكيت + قائمة تغيير الكيت إن كانت المجموعة كيت ستار مفعّلة
                  _cell(
                    Row(
                      children: [
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up
                              : Icons.keyboard_arrow_down,
                          size: 20,
                          color: isDark
                              ? Colors.purple.shade300
                              : Colors.deepPurple,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(
                                '📦 $kitName',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 12,
                                  color: isDark
                                      ? Colors.purple.shade300
                                      : Colors.deepPurple,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                              if (selectedKitName != null &&
                                  selectedKitName != kitName)
                                Text(
                                  selectedKitName,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: isDark
                                        ? Colors.grey.shade400
                                        : Colors.grey.shade600,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                            ],
                          ),
                        ),
                        if (isShutterKit &&
                            isResizableShutterKit &&
                            isGroupActive)
                          Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: _buildKitDropdown(
                              kitItem,
                            ), // زر تغيير الكيت فقط لكيتات الستار المفعّلة
                          ),
                      ],
                    ),
                    _wName,
                    backgroundColor: isDark
                        ? Colors.deepPurple.shade900.withValues(alpha: 0.3)
                        : Colors.deepPurple.shade100.withValues(alpha: 0.4),
                  ),
                  // عمود الكمية: يعرض عدد عناصر المجموعة بصيغة نصية (واحد/عنصران/عناصر)
                  _cell(
                    Text(
                      visibleCount == 1
                          ? Localization.translate('عنصر واحد', lang)
                          : visibleCount == 2
                          ? Localization.translate('عنصران', lang)
                          : (visibleCount >= 3 && visibleCount <= 10)
                          ? '$visibleCount ${Localization.translate('عناصر', lang)}'
                          : '$visibleCount ${Localization.translate('عنصر', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wQty,
                  ),
                  // صف المجموعة لا يمثل طول قص حقيقيًا.
                  _cell(
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wActualMeters,
                  ),
                  // سعر الكيت الرسمي المخزن في كتالوج مكونات الستار أو مجموع عناصره.
                  _cell(
                    Text(
                      '${effectiveKitUnitPrice.toStringAsFixed(2)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wPrice,
                  ),
                  // إجمالي سعر الكيت الرسمي × كميته.
                  _cell(
                    Text(
                      '${totalPrice.toStringAsFixed(2)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wEstimated,
                  ),
                  // التكلفة الفعلية للمجموعة (سعر الوحدة × المطلوب الحقيقي).
                  _cell(
                    Text(
                      '${totalPrice.toStringAsFixed(1)} ${Localization.translate('دج', lang)}',
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: isDark ? Colors.white70 : Colors.black87,
                        decoration: !isGroupActive
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    _wTotal,
                  ),
                  _cell(
                    Text(
                      '-',
                      style: TextStyle(
                        fontSize: 12,
                        color: isDark ? Colors.white54 : Colors.grey,
                      ),
                    ),
                    _wLen,
                  ),
                  _cell(
                    const Text(
                      '-',
                      style: TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    _wColor,
                  ),
                  // عمود التفعيل: Checkbox واحد يفعّل/يعطّل كل المجموعة دفعة واحدة
                  _cell(
                    Checkbox(
                      value: isGroupActive,
                      onChanged: (v) {
                        // توجيه التبديل حسب نوع المجموعة (OB/Demi/Verrou/كيت عادي)
                        if (isSystemOb) {
                          _handleVariantToggle(
                            'System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isDemiOb) {
                          _handleVariantToggle(
                            'Demi System OB',
                            'ob_group',
                            v ?? false,
                          );
                        } else if (isVerrouCentral) {
                          _handleVariantToggle(
                            'Verrou Central',
                            'verrou_group',
                            v ?? false,
                          );
                        } else {
                          _handleVariantToggle(
                            kitItem.originalName,
                            null,
                            v ?? false,
                          );
                        }
                      },
                    ),
                    _wCheck,
                    isLast: true,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      // ---- عناصر المجموعة الفرعية: تُضاف فقط إذا كانت المجموعة موسّعة (isExpanded) ----
      if (isExpanded) {
        // نفس منطق فلترة visibleCount أعلاه بالضبط، لضمان توافق العدد المعروض مع العناصر الفعلية
        bool isKitHeader(String name) =>
            name == 'كيت (Kit)' ||
            name == 'كيت فولي موتور (Kit Volet Moteur)' ||
            name == 'كيت فولي مانيفر (Kit Volet Manivelle)' ||
            name == 'كيت مانيفر (Kit Manivelle)' ||
            name == 'كيت حزام (Kit Sangle)' ||
            name == 'كيت فولي (Kit Volet)';
        final visibleChildren = children
            .where(
              (c) =>
                  !isKitHeader(c.originalName) &&
                  c.originalName != 'System OB' &&
                  c.originalName != 'Demi System OB' &&
                  c.originalName != 'Verrou Central',
            )
            .toList();
        widgets.addAll(
          visibleChildren.map(_buildDraggableMaterialRow),
        ); // بناء صف عادي لكل عنصر فرعي عبر _row
      }
    }
    return widgets;
  }
}
