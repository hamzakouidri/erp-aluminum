part of '../model.dart';

/// Roller shutter (box, tunnel, curtain, motor, splits) of [WindowModel].
extension WindowModelShutter on WindowModel {
  bool _isX3dShutterComponent(Map<String, dynamic> component) {
    final text =
        '${component['name'] ?? ''} ${component['shutter_subtype'] ?? ''}'
            .toLowerCase();
    // Catalogue entries may call the same blade either X3D or Extrudé.
    return text.contains('x3d') ||
        text.contains('extrud') ||
        text.contains('إكسترودي') ||
        text.contains('اكسترودي');
  }

  double? _shutterComponentDiameter(Map<String, dynamic> component) {
    final type = (component['component_type'] ?? '').toString().toLowerCase();
    final name = (component['name'] ?? '').toString().toLowerCase();
    final isMotor =
        type == 'motor' || type == 'moteur' || name.contains('moteur');
    for (final field in const ['motor_diameter', 'measurement', 'name']) {
      final value = (component[field] ?? '').toString().trim();
      // "10 Nm" is a torque, not a 10 mm motor diameter. The structured
      // motor_diameter field has priority; legacy names can still hold a
      // diameter when they do not express a torque.
      if (isMotor &&
          field != 'motor_diameter' &&
          RegExp(
            r'\d+(?:[.,]\d+)?\s*n\s*\.?\s*m',
            caseSensitive: false,
          ).hasMatch(value)) {
        continue;
      }
      final match = RegExp(r'(?<!\d)(\d{2,3}(?:[.,]\d+)?)').firstMatch(value);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', '.'));
      }
    }
    return null;
  }

  double? _shutterMotorTorque(Map<String, dynamic> component) {
    for (final field in const ['measurement', 'name']) {
      final value = (component[field] ?? '').toString().trim();
      if (value.isEmpty) continue;
      final match = RegExp(
        r'(\d+(?:[.,]\d+)?)\s*(?:n\s*\.?\s*m|nm|نيوتن)',
        caseSensitive: false,
      ).firstMatch(value);
      if (match != null) {
        return double.tryParse(match.group(1)!.replaceAll(',', '.'));
      }
      // Some older catalogues store a bare torque value in `measurement`.
      if (field == 'measurement') {
        final direct = double.tryParse(value.replaceAll(',', '.'));
        if (direct != null) return direct;
      }
    }
    return null;
  }

  bool _motorHasEmergencyCrank(Map<String, dynamic> motor) {
    final raw = motor['motor_has_emergency_crank'];
    if (raw is bool) return raw;
    if (raw is num) return raw != 0;
    final value = raw?.toString().trim().toLowerCase() ?? '';
    return value == '1' ||
        value == 'true' ||
        value == 'yes' ||
        value == 'oui' ||
        value == 'نعم';
  }

  bool _matchesShutterRole(Map<String, dynamic> component, String role) {
    final type = (component['component_type'] ?? '').toString().toLowerCase();
    final name = (component['name'] ?? '').toString().toLowerCase();
    switch (role) {
      case 'axis':
        return type == 'laxe' ||
            type == 'axe' ||
            type.contains('محور') ||
            name.contains('axe') ||
            name.contains('محور');
      case 'motor':
        return type == 'motor' ||
            type == 'moteur' ||
            name.contains('moteur') ||
            name.contains('محرك');
      case 'embout':
        return type == 'embout' ||
            name.contains('embout') ||
            name.contains('bague filet') ||
            name.contains('bague fil') ||
            name.contains('blague flit');
      case 'support_roulement':
        return type == 'support_roulement' ||
            type.contains('support roulement') ||
            name.contains('support roulement') ||
            name.contains('roulement') ||
            name.contains('سيبور رولمو');
      case 'support_moteur':
        return type == 'support_moteur' ||
            type.contains('support moteur') ||
            name.contains('support moteur') ||
            name.contains('سيبور موتور');
      case 'attache':
        return type == 'attache' ||
            type.contains('attache') ||
            name.contains('attache') ||
            name.contains('أطاش');
      case 'blade_cap':
        return type == 'bouchon_lame';
      default:
        return false;
    }
  }

  List<Map<String, dynamic>> _compatibleShutterAxes(
    Iterable<Map<String, dynamic>> rows, {
    Map<String, dynamic>? blade,
    Map<String, dynamic>? motor,
  }) {
    final selectedBlade = blade ?? componentOverrides['الشرائح (Lames)'];
    final bladeName = (selectedBlade?['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase();
    final bladeIsX3d =
        selectedBlade != null && _isX3dShutterComponent(selectedBlade);
    var candidates = rows
        .where(_matchesShutterRoleAxis)
        .map(Map<String, dynamic>.from)
        .where((axis) {
          final axisIsX3d = _isX3dShutterComponent(axis);
          return bladeIsX3d ? axisIsX3d : !axisIsX3d;
        })
        .toList();

    if (bladeName.isNotEmpty) {
      final explicitlyLinked = candidates.where((axis) {
        return (axis['shutter_subtype'] ?? '')
                .toString()
                .trim()
                .toLowerCase() ==
            bladeName;
      }).toList();
      if (explicitlyLinked.isNotEmpty) candidates = explicitlyLinked;
    }

    final motorDiameter = motor == null
        ? null
        : _shutterComponentDiameter(motor);
    if (motorDiameter != null && motorDiameter > 0) {
      candidates = candidates.where((axis) {
        final axisDiameter = _shutterComponentDiameter(axis);
        return axisDiameter != null && axisDiameter >= motorDiameter;
      }).toList();
    }

    candidates.sort((a, b) {
      final aDiameter = _shutterComponentDiameter(a) ?? double.infinity;
      final bDiameter = _shutterComponentDiameter(b) ?? double.infinity;
      return aDiameter.compareTo(bDiameter);
    });
    return candidates;
  }

  bool _matchesShutterRoleAxis(Map<String, dynamic> component) =>
      _matchesShutterRole(component, 'axis');

  /// Chooses only an axis that belongs to the selected blade.  X3D is the
  /// first decision; a motor's diameter then removes axes that are too small.
  Map<String, dynamic>? _selectCompatibleShutterAxis(
    Iterable<Map<String, dynamic>> rows, {
    Map<String, dynamic>? motor,
    bool ignoreCurrentMotor = false,
  }) {
    final selectedMotor = ignoreCurrentMotor
        ? motor
        : (motor ?? componentOverrides['المحرك (Moteur)']);
    final candidates = _compatibleShutterAxes(rows, motor: selectedMotor);
    return candidates.isEmpty ? null : candidates.first;
  }

  /// The rail is dictated by the selected blade's physical measurement.  This
  /// is especially important for Lame Second Sink Injecté, whose rail must
  /// carry the same measurement rather than retaining the default 25 mm rail.
  Future<void> _synchronizeShutterTrackWithBlade(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade == null) return;

    // Older blades did not have a separate rail measurement, so fall back to
    // their existing measurement for backward compatibility.
    final bladeSize = WindowModel.shutterMeasurementKey(
      Map<String, dynamic>.from(blade),
      preferTrackMeasurement: true,
    );
    if (bladeSize == null || bladeSize.isEmpty) return;

    final rows = await database.query(
      'ShutterComponents',
      where:
          "LOWER(TRIM(component_type)) IN ('track', 'coulisse', 'coulisses', 'glissiere') AND (is_active = 1 OR is_active IS NULL)",
    );
    final bladeIsX3d = _isX3dShutterComponent(blade);
    final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
    final candidates = WindowModel.compatibleShutterTracks(
      Map<String, dynamic>.from(blade),
      normalizeDatabaseRows(rows),
    ).where((track) => _isX3dShutterComponent(track) == bladeIsX3d).toList();
    if (candidates.isEmpty) return;

    int score(Map<String, dynamic> track) {
      final subtype = (track['shutter_subtype'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      if (bladeName.isNotEmpty && subtype == bladeName) return 0;
      final type = (track['component_type'] ?? '').toString().toLowerCase();
      if (type == 'track' || type == 'coulisse') return 1;
      if (subtype.isEmpty || subtype == 'normal') return 2;
      return 3;
    }

    candidates.sort((a, b) => score(a).compareTo(score(b)));
    final selected = Map<String, dynamic>.from(candidates.first);
    final rawPrice = selected['price_dzd'] ?? selected['price'] ?? 0.0;
    selected['calculated_price'] = rawPrice is num
        ? rawPrice.toDouble()
        : double.tryParse(rawPrice.toString()) ?? 0.0;
    componentOverrides['السكك (Coulisses)'] = selected;
    shutterGlissiere = selected['name']?.toString() ?? shutterGlissiere;
  }

  /// Keep the parts that are physically tied to a shutter blade in the
  /// ShutterComponents catalogue.  Kits are intentionally absent here: they
  /// are selected exclusively from KitBundles.
  Future<void> _synchronizeShutterPartsWithBlade(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade == null) return;

    final rows = await database.query(
      'ShutterComponents',
      where: '(is_active = 1 OR is_active IS NULL)',
    );
    final catalogue = normalizeDatabaseRows(rows);
    final colorPrices = normalizeDatabaseRows(
      await database.query('ShutterColorPrices'),
    );
    final selectedColorId = selectedDbColor?['id'] is num
        ? (selectedDbColor!['id'] as num).toInt()
        : int.tryParse('${selectedDbColor?['id'] ?? ''}');
    final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
    final isX3d = _isX3dShutterComponent(blade);

    Map<String, dynamic> withPrice(Map<String, dynamic> row) {
      final result = Map<String, dynamic>.from(row);
      result['calculated_price'] = resolveShutterComponentUnitPrice(
        component: result,
        colorPrices: colorPrices,
        selectedColorId: selectedColorId,
      );
      return result;
    }

    Map<String, dynamic>? selectForBlade(String role, String overrideKey) {
      var candidates = catalogue
          .where((row) => _matchesShutterRole(row, role))
          .where((row) => _isX3dShutterComponent(row) == isX3d)
          .toList();
      if (candidates.isEmpty) return null;

      final exact = candidates.where((row) {
        return bladeName.isNotEmpty &&
            (row['shutter_subtype'] ?? '').toString().trim().toLowerCase() ==
                bladeName;
      }).toList();
      if (exact.isNotEmpty) candidates = exact;

      final currentId = (componentOverrides[overrideKey]?['id'] as num?)
          ?.toInt();
      final current = currentId == null
          ? null
          : candidates.where(
              (row) => (row['id'] as num?)?.toInt() == currentId,
            );
      if (current != null && current.isNotEmpty) {
        return withPrice(current.first);
      }
      return withPrice(candidates.first);
    }

    // Normal motor shutters use the configured component titled/type Moteur.
    // X3D is refined later by its torque calculation in
    // _applyX3dPvcShutterRules.
    if (shutterMechanism == 'محرك' && !isX3d) {
      final motor = selectForBlade('motor', 'المحرك (Moteur)');
      if (motor == null) {
        componentOverrides.remove('المحرك (Moteur)');
      } else {
        componentOverrides['المحرك (Moteur)'] = motor;
      }
    }

    // Attaches belong to the selected blade subtype.  There is deliberately
    // no cross-subtype fallback: normal blades never borrow X3D attaches and
    // vice versa.
    final attache = selectForBlade('attache', 'أطاش (Attache)');
    if (attache == null) {
      componentOverrides.remove('أطاش (Attache)');
    } else {
      componentOverrides['أطاش (Attache)'] = attache;
    }

    // Blade end caps use the exact linked-blade field saved by the catalogue
    // dialog. They never fall back to another blade family or size.
    final linkedEndCaps = catalogue
        .where((row) => _matchesShutterRole(row, 'blade_cap'))
        .where((row) => WindowModel.isBladeEndCapLinkedTo(row, blade))
        .toList();
    if (linkedEndCaps.isEmpty) {
      componentOverrides.remove('أغطية الشفرات (Bouchons Lames)');
    } else {
      componentOverrides['أغطية الشفرات (Bouchons Lames)'] = withPrice(
        linkedEndCaps.first,
      );
    }
  }

  /// X3D shutters in a standard PVC caisson use a dedicated motorised
  /// assembly.  The motor is selected by the requested torque, and only from
  /// motors that physically fit the axis chosen for the X3D blade.
  Future<void> _applyX3dPvcShutterRules(dynamic database) async {
    final blade = componentOverrides['الشرائح (Lames)'];
    if (!hasShutter ||
        isCaissonTunnel ||
        !isPVC ||
        blade == null ||
        !_isX3dShutterComponent(blade)) {
      return;
    }

    _synchronizeShutterMechanismValue('محرك');
    final rows = await database.query(
      'ShutterComponents',
      where: '(is_active = 1 OR is_active IS NULL)',
    );
    final catalogue = normalizeDatabaseRows(rows);
    final axes = _compatibleShutterAxes(
      catalogue.where((row) => _matchesShutterRole(row, 'axis')),
      blade: Map<String, dynamic>.from(blade),
    );

    Map<String, dynamic> withPrice(Map<String, dynamic> component) {
      final result = Map<String, dynamic>.from(component);
      final rawPrice = result['price_dzd'] ?? result['price'] ?? 0.0;
      result['calculated_price'] = rawPrice is num
          ? rawPrice.toDouble()
          : double.tryParse(rawPrice.toString()) ?? 0.0;
      return result;
    }

    // The shutter height excludes the regular PVC caisson.  The required
    // torque is the stated X3D rule: surface × 12 kg/m² ÷ 1.6.
    final shutterHeightMm = math.max(0.0, height - shutterBoxHeight);
    final requiredTorque =
        (width / 1000.0) * (shutterHeightMm / 1000.0) * 12.0 / 1.6;
    final motors =
        catalogue.where((row) => _matchesShutterRole(row, 'motor')).where((
          motor,
        ) {
          final torque = _shutterMotorTorque(motor);
          if (torque == null || torque < requiredTorque) return false;
          // A declared motor diameter must fit inside at least one compatible
          // X3D axis.  Rows without the new diameter field remain selectable
          // for legacy catalogues.
          final motorDiameter = _shutterComponentDiameter(motor);
          return motorDiameter == null ||
              axes.any((axis) {
                final axisDiameter = _shutterComponentDiameter(axis);
                return axisDiameter == null || axisDiameter >= motorDiameter;
              });
        }).toList()..sort((a, b) {
          final torqueCompare = (_shutterMotorTorque(a) ?? double.infinity)
              .compareTo(_shutterMotorTorque(b) ?? double.infinity);
          if (torqueCompare != 0) return torqueCompare;
          return (_shutterComponentDiameter(a) ?? double.infinity).compareTo(
            _shutterComponentDiameter(b) ?? double.infinity,
          );
        });

    // A motor chosen explicitly in the cost table remains authoritative when
    // it still meets the required torque and fits an axis for this blade.
    // This keeps the axis tied to the motor (40/60 mm, etc.) instead of
    // replacing the user's selected motor during a refresh.
    final currentMotor = componentOverrides['المحرك (Moteur)'];
    final currentMotorId = (currentMotor?['id'] as num?)?.toInt();
    Map<String, dynamic>? chosenMotor;
    if (currentMotorId != null) {
      for (final motor in motors) {
        if ((motor['id'] as num?)?.toInt() == currentMotorId) {
          chosenMotor = motor;
          break;
        }
      }
    }
    final selectedMotor = chosenMotor == null
        ? (motors.isEmpty ? null : withPrice(motors.first))
        : withPrice(chosenMotor);
    if (selectedMotor == null) {
      componentOverrides.remove('المحرك (Moteur)');
    } else {
      componentOverrides['المحرك (Moteur)'] = selectedMotor;
    }

    final selectedAxis = axes.where((axis) {
      final motorDiameter = selectedMotor == null
          ? null
          : _shutterComponentDiameter(selectedMotor);
      final axisDiameter = _shutterComponentDiameter(axis);
      return motorDiameter == null ||
          axisDiameter == null ||
          axisDiameter >= motorDiameter;
    }).toList();
    if (selectedAxis.isEmpty) {
      componentOverrides.remove('المحور (Axe)');
    } else {
      componentOverrides['المحور (Axe)'] = withPrice(selectedAxis.first);
    }

    int relationScore(Map<String, dynamic> component) {
      final subtype = (component['shutter_subtype'] ?? '')
          .toString()
          .trim()
          .toLowerCase();
      final bladeName = (blade['name'] ?? '').toString().trim().toLowerCase();
      if (bladeName.isNotEmpty && subtype == bladeName) return 0;
      if (_isX3dShutterComponent(component)) return 1;
      if (subtype == 'normal' || subtype.isEmpty) return 2;
      return 3;
    }

    Map<String, dynamic>? preferredRole(
      String role, {
      required List<String> requiredWords,
    }) {
      final candidates = catalogue.where((component) {
        if (!_matchesShutterRole(component, role)) return false;
        final text =
            '${component['name'] ?? ''} ${component['component_type'] ?? ''}'
                .toLowerCase();
        return requiredWords.every(text.contains);
      }).toList()..sort((a, b) => relationScore(a).compareTo(relationScore(b)));
      return candidates.isEmpty ? null : withPrice(candidates.first);
    }

    // These two parts are mandatory for X3D.  Do not silently replace them
    // with a generic part: a missing catalogue row must remain visible.
    final cpr = preferredRole(
      'support_roulement',
      requiredWords: const ['cpr'],
    );
    if (cpr == null) {
      componentOverrides.remove('سيبور رولمو (Support Roulement)');
    } else {
      componentOverrides['سيبور رولمو (Support Roulement)'] = cpr;
    }
    final galvaEmbout = preferredRole('embout', requiredWords: const ['galva']);
    if (galvaEmbout == null) {
      componentOverrides.remove('الامبو (Embout)');
    } else {
      componentOverrides['الامبو (Embout)'] = galvaEmbout;
    }

    // A motor with an emergency manivelle does not need a support motor.
    if (selectedMotor == null || _motorHasEmergencyCrank(selectedMotor)) {
      componentOverrides.remove('سيبور موتور (Support Moteur)');
    } else {
      final support = preferredRole('support_moteur', requiredWords: const []);
      if (support == null) {
        componentOverrides.remove('سيبور موتور (Support Moteur)');
      } else {
        componentOverrides['سيبور موتور (Support Moteur)'] = support;
      }
    }
  }

  Future<void> ensureFrameCompatibleWithShutter() {
    return _selectNonIntegratedFrameForShutter();
  }

  /// يعيد أقسام الصناديق الفعالة (إما الصناديق المقسمة أو صندوق واحد موحد)
  List<ShutterSplitSection> get effectiveShutterSplits {
    if (!hasShutter) return const [];
    if (!isShutterSplit || shutterSplits.isEmpty) {
      if (usesProfileAngle && activeProfileAngleJunctions.isNotEmpty) {
        final frames = getFrameRects();
        if (frames.length > 1) {
          final sortedFrames = List<Rect>.from(frames)
            ..sort((a, b) => a.left.compareTo(b.left));
          return List.generate(sortedFrames.length, (i) {
            final f = sortedFrames[i];
            return ShutterSplitSection(
              width: f.width,
              leftOffset: f.left,
              customHeight: null,
              label: 'صندوق إطار ${i + 1}',
              frameIndex: i,
              mechanism: shutterMechanism,
              driveSide: shutterDriveSide,
            );
          });
        }
      }
      return [
        ShutterSplitSection(
          width: width.toDouble(),
          leftOffset: 0.0,
          customHeight: null,
          label: 'صندوق موحد',
          mechanism: shutterMechanism,
          driveSide: shutterDriveSide,
        ),
      ];
    }
    return shutterSplits;
  }

  /// فصل الصناديق تلقائياً لكل إطار (أو بناءً على فواصل 90 درجة)
  void autoSplitShutterPerFrame() {
    final frames = getFrameRects();
    if (frames.length < 2) {
      final half = (width / 2.0).roundToDouble();
      splitShutterCustomDivisions([half, width - half], startFromRight: true);
      return;
    }

    final sortedFrames = List<Rect>.from(frames)
      ..sort((a, b) => a.left.compareTo(b.left));

    final defaultDrawingHeight = height.toDouble();
    final newSplits = <ShutterSplitSection>[];
    for (int i = 0; i < sortedFrames.length; i++) {
      final f = sortedFrames[i];
      final previous = shutterSplits.where((split) => split.frameIndex == i);
      final previousSplit = previous.isEmpty ? null : previous.first;
      final frameTotalH = (hasShutter && !isCaissonTunnel)
          ? (f.height + shutterBoxHeight)
          : f.height;
      final effectiveDefaultH = (frameTotalH - defaultDrawingHeight).abs() < 1.0
          ? defaultDrawingHeight
          : frameTotalH;
      newSplits.add(
        ShutterSplitSection(
          width: f.width,
          leftOffset: f.left,
          customHeight: effectiveDefaultH,
          label: 'صندوق إطار ${i + 1}',
          frameIndex: i,
          mechanism: previousSplit?.mechanism ?? shutterMechanism,
          driveSide: previousSplit?.driveSide ?? shutterDriveSide,
        ),
      );
    }

    isShutterSplit = true;
    shutterSplitMode = 'per_frame';
    shutterSplits = newSplits;
    _saveSnapshot();
    _notifyModelListeners();
    unawaited(updateShutterDefaultsIfNeeded());
  }

  /// تقسيم الصندوق لإطار واحد بعدة عروض (البداية من اليمين كقاعدة أساسية)
  void splitShutterCustomDivisions(
    List<double> widths, {
    bool startFromRight = true,
    List<String>? mechanisms,
    List<String>? driveSides,
  }) {
    if (widths.isEmpty) return;
    final totalW = width.toDouble();
    final newSplits = <ShutterSplitSection>[];

    if (startFromRight) {
      double currentRight = totalW;
      final temp = <ShutterSplitSection>[];
      for (int i = 0; i < widths.length; i++) {
        final w = widths[i];
        final left = math.max(0.0, currentRight - w);
        temp.add(
          ShutterSplitSection(
            width: w,
            leftOffset: left,
            label: 'صندوق ${i + 1}',
            mechanism: mechanisms != null && i < mechanisms.length
                ? mechanisms[i]
                : shutterMechanism,
            driveSide: driveSides != null && i < driveSides.length
                ? driveSides[i]
                : shutterDriveSide,
          ),
        );
        currentRight = left;
      }
      temp.sort((a, b) => a.leftOffset.compareTo(b.leftOffset));
      newSplits.addAll(temp);
    } else {
      double currentLeft = 0.0;
      for (int i = 0; i < widths.length; i++) {
        final w = widths[i];
        newSplits.add(
          ShutterSplitSection(
            width: w,
            leftOffset: currentLeft,
            label: 'صندوق ${i + 1}',
            mechanism: mechanisms != null && i < mechanisms.length
                ? mechanisms[i]
                : shutterMechanism,
            driveSide: driveSides != null && i < driveSides.length
                ? driveSides[i]
                : shutterDriveSide,
          ),
        );
        currentLeft += w;
      }
    }

    isShutterSplit = true;
    shutterSplitMode = 'custom_divisions';
    shutterSplits = newSplits;
    _saveSnapshot();
    _notifyModelListeners();
    unawaited(updateShutterDefaultsIfNeeded());
  }

  /// تخصيص أو تصغير ارتفاع الستار لصندوق/إطار معين
  void setShutterSplitHeight(int index, double? newHeight) {
    if (index < 0 || index >= shutterSplits.length) return;
    final old = shutterSplits[index];
    shutterSplits[index] = ShutterSplitSection(
      width: old.width,
      leftOffset: old.leftOffset,
      customHeight: newHeight,
      label: old.label,
      frameIndex: old.frameIndex,
      mechanism: old.mechanism,
      driveSide: old.driveSide,
    );
    isShutterSplit = true;
    _saveSnapshot();
    _notifyModelListeners();
  }

  void setShutterSplitDrive(
    int index, {
    required String mechanism,
    required String driveSide,
  }) {
    if (index < 0 || index >= shutterSplits.length) return;
    final old = shutterSplits[index];
    shutterSplits[index] = ShutterSplitSection(
      width: old.width,
      leftOffset: old.leftOffset,
      customHeight: old.customHeight,
      label: old.label,
      frameIndex: old.frameIndex,
      mechanism: mechanism,
      driveSide: driveSide == 'right' ? 'right' : 'left',
    );
    isShutterSplit = true;
    _saveSnapshot();
    _notifyModelListeners();
  }

  /// دمج الصناديق والعودة لصندوق موحد
  void resetShutterSplit() {
    isShutterSplit = false;
    shutterSplits.clear();
    _saveSnapshot();
    _notifyModelListeners();
    unawaited(updateShutterDefaultsIfNeeded());
  }

  /// مزامنة وتمديد الستار تلقائياً عند تمديد أو تغيير أبعاد الإطارات
  void synchronizeShutterAfterFrameResize(double oldW, double oldH) {
    if (!hasShutter) return;
    final frames = getFrameRects();
    if (frames.isEmpty) return;

    if (isShutterSplit && shutterSplits.isNotEmpty) {
      if (shutterSplitMode == 'per_frame' || frames.length > 1) {
        final sortedFrames = List<Rect>.from(frames)
          ..sort((a, b) => a.left.compareTo(b.left));

        final defaultDrawingHeight = height.toDouble();
        final newSplits = <ShutterSplitSection>[];
        for (int i = 0; i < sortedFrames.length; i++) {
          final f = sortedFrames[i];
          final previous = shutterSplits.where(
            (split) => split.frameIndex == i,
          );
          final previousSplit = previous.isEmpty
              ? (i < shutterSplits.length ? shutterSplits[i] : null)
              : previous.first;
          final frameTotalH = (hasShutter && !isCaissonTunnel)
              ? (f.height + shutterBoxHeight)
              : f.height;
          final effectiveDefaultH =
              (frameTotalH - defaultDrawingHeight).abs() < 1.0
              ? defaultDrawingHeight
              : frameTotalH;
          newSplits.add(
            ShutterSplitSection(
              width: f.width,
              leftOffset: f.left,
              customHeight: effectiveDefaultH,
              label: 'صندوق إطار ${i + 1}',
              frameIndex: i,
              mechanism: previousSplit?.mechanism ?? shutterMechanism,
              driveSide: previousSplit?.driveSide ?? shutterDriveSide,
            ),
          );
        }
        shutterSplits = newSplits;
      } else {
        // تقسيمات مخصصة: تمديد وملاءمة العرض الإجمالي الجديد
        if (oldW > 0 && width > 0 && (oldW - width).abs() > 0.5) {
          final scale = width / oldW;
          double currentLeft = 0.0;
          final newSplits = <ShutterSplitSection>[];
          for (int i = 0; i < shutterSplits.length; i++) {
            final split = shutterSplits[i];
            final newSplitW = (i == shutterSplits.length - 1)
                ? math.max(50.0, width - currentLeft)
                : split.width * scale;
            newSplits.add(
              ShutterSplitSection(
                width: newSplitW,
                leftOffset: currentLeft,
                customHeight: split.customHeight,
                label: split.label,
                frameIndex: split.frameIndex,
                mechanism: split.mechanism,
                driveSide: split.driveSide,
              ),
            );
            currentLeft += newSplitW;
          }
          shutterSplits = newSplits;
        }
      }
    }
  }

  void _synchronizeShutterMechanismValue(String mechanism) {
    shutterMechanism = mechanism;
    if (isShutterSplit) {
      shutterSplits = shutterSplits
          .map((split) => split.copyWith(mechanism: mechanism))
          .toList();
    }
  }

  /// Applies the selected mechanism to both the unified shutter and every
  /// existing split. Keeping only the top-level value in sync caused the
  /// drawing controls and the calculated shutter kits to disagree.
  void setAllShutterMechanism(String requestedMechanism) {
    final mechanism = switch (requestedMechanism) {
      'مانيفال' || 'مانيفر' => 'منايفال',
      'محرك' => 'محرك',
      _ => 'حزام',
    };
    final splitsAlreadyMatch = shutterSplits.every(
      (split) => (split.mechanism ?? shutterMechanism) == mechanism,
    );
    if (shutterMechanism == mechanism && splitsAlreadyMatch) return;

    _saveSnapshot();
    _synchronizeShutterMechanismValue(mechanism);
    if (mechanism != 'محرك') {
      motorHasInterrupteur = false;
      motorHasTelecommande = false;
    }
    _notifyModelListeners();
  }

  void setAllShutterDriveSide(String side) {
    shutterDriveSide = side;
    if (isShutterSplit) {
      shutterSplits = shutterSplits
          .map((s) => s.copyWith(driveSide: side))
          .toList();
    }
  }

  void setShutterBladeWarningCatalogue(List<Map<String, dynamic>> blades) {
    _shutterBladeWarningCatalogue = blades;
  }

  /// Blade capacity is checked against the widest independent shutter, not
  /// the full window opening. Once the box is split, every section has its
  /// own curtain and may therefore use the smallest blade that supports it.
  double get effectiveShutterBladeWidthMm {
    final splits = effectiveShutterSplits;
    if (splits.isEmpty) return width.toDouble();
    return splits.fold<double>(
      0.0,
      (widest, split) => math.max(widest, split.width),
    );
  }

  Map<String, dynamic>? get recommendedShutterBlade {
    if (!hasShutter) return null;
    final raw = componentOverrides['الشرائح (Lames)'];
    if (raw is! Map) return null;
    final blade = Map<String, dynamic>.from(raw);
    final limit = _shutterBladeEffectiveMaxWidthMm(blade);
    final requiredWidth = effectiveShutterBladeWidthMm;
    if (requiredWidth <= limit) return null;

    final candidates =
        _shutterBladeWarningCatalogue
            .where(
              (candidate) =>
                  _shutterBladeEffectiveMaxWidthMm(candidate) >= requiredWidth,
            )
            .toList()
          ..sort((a, b) {
            final result = _shutterBladeEffectiveMaxWidthMm(
              a,
            ).compareTo(_shutterBladeEffectiveMaxWidthMm(b));
            if (result != 0) return result;
            return (a['id'] as num? ?? 0).compareTo(b['id'] as num? ?? 0);
          });

    if (candidates.isNotEmpty) {
      return candidates.first;
    }
    return null;
  }

  void applyRecommendedShutterBlade() {
    final recommended = recommendedShutterBlade;
    if (recommended == null) return;
    final automaticSelection = Map<String, dynamic>.from(recommended)
      ..['manual_selection'] = false
      ..['user_selected'] = false
      ..['automatic_selection'] = true;
    componentOverrides['الشرائح (Lames)'] = automaticSelection;
    shutterLame = automaticSelection['name']?.toString() ?? shutterLame;
    final subtype = (automaticSelection['shutter_subtype']?.toString() ?? '')
        .toLowerCase();
    final name = (automaticSelection['name']?.toString() ?? '').toLowerCase();
    if (subtype == 'extruded' ||
        name.contains('extruded') ||
        name.contains('إكسترودي')) {
      _synchronizeShutterMechanismValue('محرك');
    }
    shutterMaximumWidthMm = _shutterBladeConfiguredMaxWidthMm(
      automaticSelection,
    );
    _notifyModelListeners();
  }

  String? localizedShutterWidthWarning([
    AppLanguage lang = AppLanguage.arabic,
  ]) {
    if (!hasShutter) return null;
    final raw = componentOverrides['الشرائح (Lames)'];
    if (raw is! Map) return null;
    final blade = Map<String, dynamic>.from(raw);
    final limit = _shutterBladeEffectiveMaxWidthMm(blade);
    final requiredWidth = effectiveShutterBladeWidthMm;
    if (requiredWidth <= limit) return null;

    final recommended = recommendedShutterBlade;
    final bladeName = blade['name']?.toString() ?? shutterLame;
    final wStr = requiredWidth.toStringAsFixed(0);
    final limitStr = limit.toStringAsFixed(0);

    if (lang == AppLanguage.french) {
      final base =
          'La largeur du volet ($wStr mm) dépasse la limite maximale de la lame «$bladeName» ($limitStr mm).';
      if (recommended != null) {
        final recName = recommended['name']?.toString() ?? '';
        final recLimit = _shutterBladeEffectiveMaxWidthMm(
          recommended,
        ).toStringAsFixed(0);
        return '$base Il est recommandé de choisir «$recName» (max $recLimit mm), sélectionnée automatiquement par le système.';
      }
      return _shutterBladeWarningCatalogue.isEmpty
          ? '$base Veuillez choisir une lame adaptée à cette largeur.'
          : '$base Aucune lame disponible ne supporte cette largeur ; vérifiez les dimensions ou le catalogue.';
    } else if (lang == AppLanguage.english) {
      final base =
          'Shutter width ($wStr mm) exceeds the maximum limit for blade «$bladeName» ($limitStr mm).';
      if (recommended != null) {
        final recName = recommended['name']?.toString() ?? '';
        final recLimit = _shutterBladeEffectiveMaxWidthMm(
          recommended,
        ).toStringAsFixed(0);
        return '$base It is recommended to choose «$recName» (max $recLimit mm), automatically selected by the system.';
      }
      return _shutterBladeWarningCatalogue.isEmpty
          ? '$base Please select a blade that supports this width.'
          : '$base No blade available supports this width; please check dimensions or catalogue limits.';
    } else {
      final base =
          'عرض الستار $wStr مم يتجاوز الحد الأقصى للشفرة «$bladeName»: $limitStr مم.';
      if (recommended != null) {
        final recName = recommended['name']?.toString() ?? '';
        final recLimit = _shutterBladeEffectiveMaxWidthMm(
          recommended,
        ).toStringAsFixed(0);
        return '$base يُنصح بتغيير الشفرة إلى «$recName» (الحد الأقصى $recLimit مم)، وهي التي سيختارها النظام في الوضع التلقائي.';
      }
      return _shutterBladeWarningCatalogue.isEmpty
          ? '$base اختر شفرة تتحمل هذا العرض.'
          : '$base لا توجد شفرة متاحة تتحمل هذا العرض؛ راجع الأبعاد أو حدود الشفرات في الكتالوج.';
    }
  }

  String? get shutterWidthWarning =>
      localizedShutterWidthWarning(AppLanguage.arabic);

  double get maximumShutterBarLengthMm {
    double readLength(Object? raw) {
      final value = raw is num
          ? raw.toDouble()
          : double.tryParse(raw?.toString() ?? '') ?? 0.0;
      if (value <= 0) return 6000.0;
      final millimetres = value > 100.0 ? value : value * 1000.0;
      return math.min(6000.0, millimetres);
    }

    final blade = componentOverrides['الشرائح (Lames)'];
    if (blade is Map) {
      return readLength(blade['bar_length_m'] ?? blade['bar_length']);
    }
    return 6000.0;
  }

  double get maximumAllowedShutterWidthMm =>
      math.min(maximumShutterBarLengthMm, shutterMaximumWidthMm ?? 6000.0);

  double _shutterBladeConfiguredMaxWidthMm(Map<String, dynamic> blade) {
    final raw = blade['max_width_mm'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
    if (value <= 0) return 6000.0;
    return math.min(6000.0, value);
  }

  double _shutterBladeBarLimitMm(Map<String, dynamic> blade) {
    final raw = blade['bar_length_m'] ?? blade['bar_length'];
    final value = raw is num
        ? raw.toDouble()
        : double.tryParse(raw?.toString() ?? '') ?? 0.0;
    if (value <= 0) return 6000.0;
    final millimetres = value > 100.0 ? value : value * 1000.0;
    return math.min(6000.0, millimetres);
  }

  double _shutterBladeEffectiveMaxWidthMm(Map<String, dynamic> blade) {
    return math.min(
      _shutterBladeConfiguredMaxWidthMm(blade),
      _shutterBladeBarLimitMm(blade),
    );
  }

  Future<void> updateShutterLame(String name) async {
    shutterLame = name;
    final database = await db.db;
    if (database != null) {
      final exactMatch = await database.query(
        'ShutterComponents',
        where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [name],
      );
      if (exactMatch.isNotEmpty) {
        final selected = Map<String, dynamic>.from(exactMatch.first);
        selected['manual_selection'] = true;
        selected['user_selected'] = true;
        selected['automatic_selection'] = false;
        componentOverrides['الشرائح (Lames)'] = selected;
      }
    }
    await updateShutterDefaultsIfNeeded();
    _notifyModelListeners();
  }

  double get shutterDrawingHeight {
    if (!hasShutter || !isShutterSplit || shutterSplits.isEmpty) {
      return height.toDouble();
    }
    return shutterSplits.fold<double>(height.toDouble(), (maximum, split) {
      final splitHeight = split.customHeight ?? height.toDouble();
      return math.max(maximum, splitHeight);
    });
  }

  bool get shutterIsLongerThanWindow =>
      hasShutter && shutterDrawingHeight > height + 0.5;

  double get shutterBoxHeight {
    if (!(hasShutter && !hasArchOrSlant)) return 0.0;
    if (isCaissonTunnel) {
      return caissonTunnelHeight;
    }
    if (customShutterBoxHeight != null) {
      return customShutterBoxHeight!;
    }
    if (height <= 1600) return 155.0;
    if (height <= 2400) return 185.0;
    return 205.0;
  }

  void _synchronizeZonesAfterShutterBoxChange(
    double previousBoxHeight,
    double nextBoxHeight,
  ) {
    if ((previousBoxHeight - nextBoxHeight).abs() <= 0.1 || zones.isEmpty) {
      _synchronizeSingleZoneWithOuterFrame();
      return;
    }

    if (zones.length == 1) {
      _synchronizeSingleZoneWithOuterFrame();
      return;
    }

    final previousTop = previousBoxHeight + profileThickness;
    final nextTop = nextBoxHeight + profileThickness;
    final bottomFrame = hasBottomFrame ? profileThickness : 0.0;
    final innerBottom = height - bottomFrame;
    final previousHeight = innerBottom - previousTop;
    final nextHeight = innerBottom - nextTop;
    if (previousHeight <= 0 || nextHeight <= 0) return;

    final scale = nextHeight / previousHeight;
    for (final zone in zones) {
      final top = nextTop + (zone.boundary.top - previousTop) * scale;
      final bottom = nextTop + (zone.boundary.bottom - previousTop) * scale;
      zone.boundary = Rect.fromLTRB(
        zone.boundary.left,
        top,
        zone.boundary.right,
        bottom,
      );
    }
  }

  void setTunnelConsoleGroup(int group) {
    final value = group == 2 ? 2 : 1;
    if (tunnelConsoleGroup == value) return;
    _saveSnapshot();
    tunnelConsoleGroup = value;
    _notifyModelListeners();
  }

  void setCaissonTunnelHeight(double value) {
    if (caissonTunnelHeight == value) return;
    _saveSnapshot();
    final previousBoxHeight = shutterBoxHeight;
    caissonTunnelHeight = value;
    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);
    lastLayoutSize = null;
    _notifyModelListeners();
  }

  void setManualShutterBoxHeight(double value) {
    if (value <= 0 || customShutterBoxHeight == value) return;
    _saveSnapshot();
    final previousBoxHeight = shutterBoxHeight;
    customShutterBoxHeight = value;
    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);
    lastLayoutSize = null;
    _notifyModelListeners();
  }

  Map<String, dynamic>? get effectiveShutterColor =>
      selectedShutterColor ?? selectedDbColor;

  Future<void> updateShutterDefaultsIfNeeded() async {
    if (!hasShutter) return;

    final previousBoxHeight = shutterBoxHeight;
    shutterMaximumWidthMm = null;
    final database = await db.db;
    Map<String, dynamic>? blade;
    final rawBlade = componentOverrides['الشرائح (Lames)'];
    if (rawBlade is Map) {
      blade = Map<String, dynamic>.from(rawBlade);
    }

    // The limits table is blade-specific. On the first shutter activation the
    // blade may not have been loaded yet, so resolve it before choosing a box.
    if (blade == null && database != null) {
      var rows = await database.query(
        'ShutterComponents',
        where: 'name = ? AND (is_active = 1 OR is_active IS NULL)',
        whereArgs: [shutterLame],
        limit: 1,
      );
      if (rows.isEmpty) {
        rows = await database.query(
          'ShutterComponents',
          where:
              "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
          limit: 1,
        );
      }
      if (rows.isNotEmpty) {
        final resolvedBlade = Map<String, dynamic>.from(rows.first);
        blade = resolvedBlade;
        componentOverrides['الشرائح (Lames)'] = resolvedBlade;
        shutterLame = resolvedBlade['name']?.toString() ?? shutterLame;
      }
    }

    // Saved drawings can contain an older, reduced blade map. Refresh the
    // limit fields from the catalogue so automatic selection and warnings
    // always use the current database value.
    if (database != null && blade != null && blade['id'] != null) {
      final bladeId = (blade['id'] as num?)?.toInt();
      if (bladeId != null) {
        final catalogRows = await database.query(
          'ShutterComponents',
          where: 'id = ?',
          whereArgs: [bladeId],
          limit: 1,
        );
        if (catalogRows.isNotEmpty) {
          final hydrated = Map<String, dynamic>.from(blade);
          for (final key in const [
            'name',
            'component_type',
            'max_width_mm',
            'bar_length_m',
            'shutter_subtype',
          ]) {
            hydrated[key] = catalogRows.first[key];
          }
          blade = hydrated;
          shutterLame = hydrated['name']?.toString() ?? shutterLame;
          componentOverrides['الشرائح (Lames)'] = hydrated;
        }
      }
    }

    // 1. Check for extruded blade auto-switch (applies to all, including tunnel boxes!)
    if (blade != null) {
      final bladeSubtype = (blade['shutter_subtype']?.toString() ?? '')
          .toLowerCase();
      final bladeName = (blade['name']?.toString() ?? '').toLowerCase();
      if (bladeSubtype == 'extruded' ||
          bladeName.contains('extruded') ||
          bladeName.contains('إكسترودي') ||
          (isPVC && !isCaissonTunnel && _isX3dShutterComponent(blade))) {
        _synchronizeShutterMechanismValue('محرك');
      }
    }

    // Choose a safe blade automatically when the current blade was not picked
    // by the user.  The smallest blade that supports the current window is
    // preferred, which prevents a weak blade from being used while avoiding
    // an unnecessarily oversized blade.  A manual choice is never replaced:
    // it remains in the drawing/BOM and receives a clear warning instead.
    final requiredBladeWidthMm = effectiveShutterBladeWidthMm;
    if (database != null && requiredBladeWidthMm > 0) {
      try {
        final bladeRows = await database.query(
          'ShutterComponents',
          where:
              "LOWER(TRIM(component_type)) IN ('blade', 'lame') AND (is_active = 1 OR is_active IS NULL)",
          orderBy: 'name ASC',
        );
        final blades = bladeRows
            .map(Map<String, dynamic>.from)
            .where(WindowModel.isShutterBladeComponent)
            .toList();
        blades.sort((a, b) {
          final limitCompare = _shutterBladeEffectiveMaxWidthMm(
            a,
          ).compareTo(_shutterBladeEffectiveMaxWidthMm(b));
          if (limitCompare != 0) return limitCompare;
          return (a['id'] as num? ?? 0).compareTo(b['id'] as num? ?? 0);
        });
        _shutterBladeWarningCatalogue = blades;
        final currentBladeIsManual = _componentWasManuallySelected(blade);

        if (blades.isNotEmpty && !currentBladeIsManual) {
          final currentId = (blade?['id'] as num?)?.toInt();
          final currentLimit = blade == null
              ? 0.0
              : _shutterBladeEffectiveMaxWidthMm(blade);
          final currentSupportsWidth =
              blade != null && currentLimit >= requiredBladeWidthMm;
            final compatible = blades
                .where(
                  (candidate) =>
                    _shutterBladeEffectiveMaxWidthMm(candidate) >=
                    requiredBladeWidthMm,
                )
                .toList();
            final replacement = compatible.isNotEmpty
                ? compatible.first
                : blades.last;
            final replacementId = (replacement['id'] as num?)?.toInt();

          // Re-evaluate automatic choices in both directions. A wider opening
          // may upgrade to X3D, while splitting that opening must downgrade to
          // the smallest suitable normal blade instead of keeping X3D.
          if (!currentSupportsWidth || replacementId != currentId) {
            if (replacementId != null && replacementId != currentId) {
              final automaticSelection = Map<String, dynamic>.from(replacement)
                ..['manual_selection'] = false
                ..['user_selected'] = false
                ..['automatic_selection'] = true;
              componentOverrides['الشرائح (Lames)'] = automaticSelection;
              blade = automaticSelection;
              shutterLame =
                  automaticSelection['name']?.toString() ?? shutterLame;
            }
          }
        }

        if (blade != null) {
          // The automatic replacement may have selected an extruded blade;
          // apply the motor requirement to the replacement as well.
          final replacementSubtype =
              (blade['shutter_subtype']?.toString() ?? '').toLowerCase();
          final replacementName = (blade['name']?.toString() ?? '')
              .toLowerCase();
          if (replacementSubtype == 'extruded' ||
              replacementName.contains('extruded') ||
              replacementName.contains('إكسترودي') ||
              (isPVC && !isCaissonTunnel && _isX3dShutterComponent(blade))) {
            _synchronizeShutterMechanismValue('محرك');
          }
          shutterMaximumWidthMm = _shutterBladeConfiguredMaxWidthMm(blade);
        }
      } catch (e) {
        print('Error resolving shutter blade width limit: $e');
      }
    }

    if (isCaissonTunnel) {
      if (database != null) {
        await _synchronizeShutterTrackWithBlade(database);
        await _synchronizeShutterPartsWithBlade(database);
      }
      _notifyModelListeners();
      return;
    }

    shutterHeightWarning = null; // Clear previous warning

    // Local helper to extract size from component
    double? getLocalComponentSize(Map<String, dynamic>? component) {
      if (component == null) return null;
      final meas = (component['measurement'] ?? '').toString().trim();
      String? sizeStr;
      if (meas.isNotEmpty) {
        sizeStr = meas.replaceAll('.', '').replaceAll(',', '');
      } else {
        final name = component['name'].toString();
        final regExp = RegExp(r'\d+(\.\d+)?');
        final match = regExp.firstMatch(name);
        if (match != null) {
          sizeStr = match.group(0)!.replaceAll('.', '');
        }
      }
      if (sizeStr != null) {
        double sz = double.tryParse(sizeStr) ?? 0.0;
        if (sz == 15.5) sz = 155.0;
        if (sz == 18.5) sz = 185.0;
        if (sz == 20.5) sz = 205.0;
        if (sz == 15.0) sz = 150.0;
        if (sz == 18.0) sz = 180.0;
        if (sz == 20.0) sz = 200.0;
        if (sz < 100.0) sz = sz * 10.0;
        return sz;
      }
      return null;
    }

    if (database != null) {
      if (blade != null && blade['id'] != null) {
        final bladeId = blade['id'];
        try {
          final List<Map<String, dynamic>> limits = await database.query(
            'ShutterBoxLimits',
            where: 'blade_id = ?',
            whereArgs: [bladeId],
            orderBy: 'box_size ASC',
          );

          double? chosenBoxSize;
          final rawManualBox = componentOverrides['الصندوق (Caisson)'];
          final manualBox = rawManualBox is Map
              ? Map<String, dynamic>.from(rawManualBox)
              : null;
          final manualBoxWasUserSelected =
              manualBox != null &&
              (manualBox['manual_selection'] == true ||
                  manualBox['is_manual_selection'] == true ||
                  manualBox['user_selected'] == true);
          if (manualBoxWasUserSelected && manualBox['id'] != -999) {
            chosenBoxSize = getLocalComponentSize(manualBox);
          }

          final resolution = WindowModel.resolveShutterBoxFromLimits(
            windowHeight: height,
            limits: limits,
            manuallySelectedBoxSize: chosenBoxSize,
          );
          if (resolution != null) {
            customShutterBoxHeight = resolution.boxSize;
            shutterHeightWarning = resolution.exceedsAllLimits
                ? 'لا يمكن تركيب هذا الستار: ارتفاع النافذة '
                      '${height.toStringAsFixed(0)} مم يتجاوز الحد الأقصى '
                      '${resolution.maximumSupportedHeight.toStringAsFixed(0)} مم. '
                      'تم اختيار أكبر صندوق '
                      '${resolution.boxSize.toStringAsFixed(0)} مم للكميات.'
                : null;
          } else {
            // Height-based fallback if no limits in DB
            double minFallback = 155.0;
            if (height > 1600 && height <= 2400) {
              minFallback = 185.0;
            } else if (height > 2400) {
              minFallback = 205.0;
            }

            if (manualBoxWasUserSelected &&
                chosenBoxSize != null &&
                chosenBoxSize >= minFallback) {
              customShutterBoxHeight = chosenBoxSize;
            } else {
              customShutterBoxHeight = minFallback;
            }
            shutterHeightWarning = null;
          }
        } catch (e) {
          print('Error loading shutter box limits from database: $e');
          customShutterBoxHeight = null;
          shutterHeightWarning = null;
        }
      } else {
        customShutterBoxHeight = null;
      }
    } else {
      customShutterBoxHeight = null;
    }

    _synchronizeZonesAfterShutterBoxChange(previousBoxHeight, shutterBoxHeight);

    bool isSameSize(String? size1, String? size2) {
      if (size1 == null || size2 == null) return false;
      final s1 = size1.replaceAll(RegExp(r'[^0-9]'), '').trim();
      final s2 = size2.replaceAll(RegExp(r'[^0-9]'), '').trim();
      if (s1.length >= 2 && s2.length >= 2) {
        return s1.substring(0, 2) == s2.substring(0, 2);
      }
      return s1 == s2;
    }

    final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
    final targetDigits = targetSize.toStringAsFixed(0);

    bool caissonMismatch = false;
    final caisson = componentOverrides['الصندوق (Caisson)'];
    if (caisson != null) {
      final sizeStr = getComponentSize(caisson);
      if (sizeStr != null) {
        final cleanSize = sizeStr.replaceAll(RegExp(r'[\s.,]'), '').trim();
        if (!isSameSize(cleanSize, targetDigits)) caissonMismatch = true;
      } else {
        caissonMismatch = true;
      }
    } else {
      caissonMismatch = true;
    }

    final isMotor = shutterMechanism == 'محرك';
    final isCrank =
        shutterMechanism == 'منايفال' ||
        shutterMechanism == 'مانيفال' ||
        shutterMechanism == 'مانيفر';
    // These overrides only remember a manual choice made from KitBundles.
    // They must never be refilled from ShutterComponents merely because the
    // caisson size changed.
    if (isMotor) {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else if (isCrank) {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي (Kit Volet)');
    } else {
      componentOverrides.remove('كيت (Kit)');
      componentOverrides.remove('كيت فولي موتور (Kit Volet Moteur)');
      componentOverrides.remove('كيت فولي مانيفر (Kit Volet Manivelle)');
      componentOverrides.remove('كيت مانيفر (Kit Manivelle)');
    }

    final myDb = await db.db;
    if (myDb != null) {
      Future<void> assignShutterDefault(
        String overrideName,
        List<String> keywords,
      ) async {
        List<Map<String, dynamic>> res = [];
        if (overrideName == 'الشرائح (Lames)' && shutterLame.isNotEmpty) {
          try {
            res = await myDb.query(
              'ShutterComponents',
              where: "name = ? AND (is_active = 1 OR is_active IS NULL)",
              whereArgs: [shutterLame],
            );
          } catch (e) {
            print(
              'Error query exact shutterLame in updateShutterDefaultsIfNeeded: $e',
            );
          }
        }
        if (res.isEmpty) {
          final ruleRole = switch (overrideName) {
            'الصندوق (Caisson)' => 'shutter_box',
            'الشرائح (Lames)' => 'shutter_blade',
            'الشريحة النهائية (Lame Finale)' => 'shutter_final_blade',
            'السكك (Coulisses)' => 'shutter_track',
            'المحور (Axe)' => 'shutter_axis',
            _
                when overrideName.contains('كيت') ||
                    overrideName.contains('Kit') =>
              'shutter_kit',
            _ => '',
          };
          if (ruleRole.isNotEmpty) {
            final ruleRows = await db.getCatalogItemRules(
              itemTable: 'ShutterComponents',
              roleKeys: [ruleRole],
            );
            for (final rule in ruleRows) {
              if (rule['show_in_quantity'] == 0) continue;
              final itemId = (rule['item_id'] as num?)?.toInt();
              if (itemId == null) continue;
              final rows = await myDb.query(
                'ShutterComponents',
                where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
                whereArgs: [itemId],
                limit: 1,
              );
              if (rows.isEmpty) continue;
              res = rows;
              break;
            }
          }
        }
        if (res.isEmpty) {
          String whereClause = keywords
              .map((_) => 'name LIKE ? OR component_type LIKE ?')
              .join(' OR ');
          List<String> args = [];
          for (var kw in keywords) {
            args.addAll(['%$kw%', '%$kw%']);
          }
          try {
            res = await myDb.query(
              'ShutterComponents',
              where: "($whereClause) AND (is_active = 1 OR is_active IS NULL)",
              whereArgs: args,
            );
          } catch (error) {
            reportCatalogIssue('ShutterComponents', error);
          }
        }
        try {
          if (overrideName == 'الشرائح (Lames)') {
            res = res.where(WindowModel.isShutterBladeComponent).toList();
          }
          if (res.isNotEmpty) {
            Map<String, dynamic>? bestMatch;

            if (overrideName == 'الشرائح (Lames)') {
              // Search for 43 or x
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('43') || name.contains('x')) {
                  if (!name.contains('final') &&
                      !name.contains('finale') &&
                      !name.contains('نهائي')) {
                    bestMatch = row;
                    break;
                  }
                }
              }
            } else if (overrideName == 'السكك (Coulisses)') {
              // Search for 25
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('25')) {
                  bestMatch = row;
                  break;
                }
              }
            } else if (overrideName == 'الشريحة النهائية (Lame Finale)' ||
                overrideName.contains('نهائ')) {
              // Search for 45
              for (var row in res) {
                final name = row['name'].toString().toLowerCase();
                if (name.contains('45')) {
                  bestMatch = row;
                  break;
                }
              }
            } else if (overrideName == 'المحور (Axe)' ||
                overrideName.contains('محور')) {
              bestMatch = _selectCompatibleShutterAxis(res);
            } else if (overrideName == 'الصندوق (Caisson)' ||
                overrideName.contains('Kit') ||
                overrideName.contains('كيت')) {
              final targetSize = shutterBoxHeight; // 155.0, 185.0, 205.0
              final targetDigits = targetSize.toStringAsFixed(0);
              for (var row in res) {
                final rowSize = getComponentSize(row);
                if (rowSize != null) {
                  final cleanRowSize = rowSize
                      .replaceAll(RegExp(r'[\s.,]'), '')
                      .trim();
                  if (cleanRowSize == targetDigits) {
                    bestMatch = row;
                    break;
                  }
                }
              }
            }

            final isAxis =
                overrideName == 'المحور (Axe)' || overrideName.contains('محور');
            if (!isAxis || bestMatch != null) {
              componentOverrides[overrideName] = Map<String, dynamic>.from(
                bestMatch ?? res.first,
              );
            }
          }
        } catch (e) {
          print('Error updating shutter default for $overrideName: $e');
        }
      }

      Future<double> resolveShutterAccessoryPrice(
        Map<String, dynamic> accessory,
      ) async {
        final accessoryId = accessory['id'];
        if (accessoryId == null) return 0.0;
        final selectedColorId = effectiveShutterColor?['id'];
        try {
          if (selectedColorId != null) {
            final colorRows = await myDb.query(
              'AccessoryColorPrices',
              columns: const ['price'],
              where: 'accessory_id = ? AND color_id = ?',
              whereArgs: [accessoryId, selectedColorId],
              limit: 1,
            );
            if (colorRows.isNotEmpty) {
              final value = colorRows.first['price'];
              final price = value is num
                  ? value.toDouble()
                  : double.tryParse(value?.toString() ?? '') ?? 0.0;
              if (price > 0) return price;
            }
          }
        } catch (error) {
          reportCatalogIssue('AccessoryColorPrices (shutter accessory price)', error);
        }
        final rawPrice = accessory['price_dzd'] ?? accessory['price'];
        return rawPrice is num
            ? rawPrice.toDouble()
            : double.tryParse(rawPrice?.toString() ?? '') ?? 0.0;
      }

      Future<void> assignShutterScrewDefault(
        String overrideName,
        String flagColumn,
        List<String> keywords,
      ) async {
        if (componentOverrides.containsKey(overrideName)) return;
        final ruleRole = switch (flagColumn) {
          'is_kit_screw' => 'kit_screw',
          'is_caisson_screw' => 'box_screw',
          'is_moteur_screw' => 'motor_screw',
          _ => '',
        };
        if (ruleRole.isNotEmpty) {
          final ruleRows = await db.getCatalogItemRules(
            itemTable: 'Accessories',
            roleKeys: [ruleRole],
          );
          for (final rule in ruleRows) {
            if (rule['show_in_quantity'] == 0) continue;
            final itemId = (rule['item_id'] as num?)?.toInt();
            if (itemId == null) continue;
            final rows = await myDb.query(
              'Accessories',
              where: 'id = ? AND (is_active = 1 OR is_active IS NULL)',
              whereArgs: [itemId],
              limit: 1,
            );
            if (rows.isEmpty) continue;
            final selected = Map<String, dynamic>.from(rows.first);
            selected['calculated_price'] = await resolveShutterAccessoryPrice(
              selected,
            );
            selected['catalog_source'] = 'Accessories';
            componentOverrides[overrideName] = selected;
            return;
          }
        }
        const screwKeywords = ['vis', 'screw', 'برغي', 'براغي'];
        final keywordClauses = <String>[];
        final screwClauses = <String>[];
        final keywordArgs = <Object?>[];
        final screwArgs = <Object?>[];
        for (final keyword in keywords) {
          keywordClauses.add('LOWER(name) LIKE ?');
          keywordClauses.add('LOWER(type) LIKE ?');
          keywordArgs.add('%${keyword.toLowerCase()}%');
          keywordArgs.add('%${keyword.toLowerCase()}%');
        }
        for (final keyword in screwKeywords) {
          screwClauses.add('LOWER(name) LIKE ?');
          screwClauses.add('LOWER(type) LIKE ?');
          screwArgs.add('%${keyword.toLowerCase()}%');
          screwArgs.add('%${keyword.toLowerCase()}%');
        }
        final args = <Object?>[...keywordArgs, ...screwArgs];
        try {
          final rows = await myDb.query(
            'Accessories',
            where:
                '($flagColumn = 1 OR ((${keywordClauses.join(' OR ')}) AND (${screwClauses.join(' OR ')}))) AND (is_active = 1 OR is_active IS NULL)',
            whereArgs: args,
            orderBy: 'CASE WHEN $flagColumn = 1 THEN 0 ELSE 1 END ASC, id ASC',
            limit: 1,
          );
          if (rows.isEmpty) return;
          final selected = Map<String, dynamic>.from(rows.first);
          selected['calculated_price'] = await resolveShutterAccessoryPrice(
            selected,
          );
          selected['catalog_source'] = 'Accessories';
          componentOverrides[overrideName] = selected;
        } catch (_) {
          try {
            final rows = await myDb.query(
              'Accessories',
              where:
                  '((${keywordClauses.join(' OR ')}) AND (${screwClauses.join(' OR ')})) AND (is_active = 1 OR is_active IS NULL)',
              whereArgs: args,
              orderBy: 'id ASC',
              limit: 1,
            );
            if (rows.isEmpty) return;
            final selected = Map<String, dynamic>.from(rows.first);
            selected['calculated_price'] = await resolveShutterAccessoryPrice(
              selected,
            );
            selected['catalog_source'] = 'Accessories';
            componentOverrides[overrideName] = selected;
          } catch (error) {
            reportCatalogIssue('Accessories (shutter screws)', error);
          }
        }
      }

      if (caissonMismatch) {
        await assignShutterDefault('الصندوق (Caisson)', [
          'box',
          'صندوق',
          'caisson',
        ]);
      }
      // Ensure Lames, Coulisse, Lame Finale, and Axe exist
      if (!componentOverrides.containsKey('الشرائح (Lames)')) {
        await assignShutterDefault('الشرائح (Lames)', [
          'blade',
          'شريح',
          'lame',
        ]);
      }
      if (!componentOverrides.containsKey('الشريحة النهائية (Lame Finale)')) {
        await assignShutterDefault('الشريحة النهائية (Lame Finale)', [
          'final_blade',
          'lame final',
          'نهائي',
        ]);
      }
      if (!componentOverrides.containsKey('السكك (Coulisses)')) {
        await assignShutterDefault('السكك (Coulisses)', [
          'track',
          'سك',
          'coulisse',
        ]);
      }

      await _synchronizeShutterTrackWithBlade(myDb);
      await _synchronizeShutterPartsWithBlade(myDb);

      // Keep the automatic axis in sync with the selected blade first, then
      // with the motor diameter.  The old 60/40 equality rule could select an
      // incompatible X3D axis or a tube smaller than its motor.
      final axisRows = await myDb.query(
        'ShutterComponents',
        where:
            "(LOWER(component_type) IN ('laxe', 'axe') OR LOWER(name) LIKE '%axe%' OR name LIKE '%محور%') AND (is_active = 1 OR is_active IS NULL)",
      );
      final preferredAxis = _selectCompatibleShutterAxis(axisRows);
      final currentAxe = componentOverrides['المحور (Axe)'];
      if (preferredAxis == null) {
        // Do not retain a known-incompatible axis when the catalogue has no
        // matching one for the blade/motor combination.
        componentOverrides.remove('المحور (Axe)');
      } else {
        final currentId = (currentAxe?['id'] as num?)?.toInt();
        final preferredId = (preferredAxis['id'] as num?)?.toInt();
        if (currentId != preferredId) {
          await assignShutterDefault('المحور (Axe)', ['laxe', 'axe', 'محور']);
        }
      }
      await assignShutterScrewDefault('براغي الكيت', 'is_kit_screw', [
        'kit',
        'كيت',
      ]);
      await assignShutterScrewDefault('براغي الصندوق', 'is_caisson_screw', [
        'caisson',
        'box',
        'صندوق',
      ]);
      await assignShutterScrewDefault('براغي المحرك', 'is_moteur_screw', [
        'moteur',
        'motor',
        'محرك',
      ]);

      // An X3D/Extrudé blade in a regular PVC caisson has a fixed assembly
      // rule. Apply it after the caisson and ordinary kit defaults are ready
      // so the table receives the linked axis, motor and support parts in one
      // refresh.
      await _applyX3dPvcShutterRules(myDb);

      _notifyModelListeners();
    }
  }

  /// A regular box above an aluminium window requires a plain frame. A tunnel
  /// box is behind the wall and permits the frame's integrated side cover.
  Future<void> _selectNonIntegratedFrameForShutter() async {
    if (!hasShutter || isCaissonTunnel || isFramePVC) return;
    final series = activeFrameSeries;
    if (series == null) return;
    final revision = _sideCoverSelectionRevision;

    final currentFrame = activeFrameOverride;
    final hasIntegratedFrame = currentFrame != null
        ? _overrideHasIntegratedSideCover(currentFrame)
        : _currentFrameHasIntegratedSideCover;
    final currentAllowsSideCover = currentFrame != null
        ? _overrideAllowsStandaloneSideCover(currentFrame)
        : true;
    if (!hasIntegratedFrame && currentAllowsSideCover) {
      return;
    }

    if (_frameMapWasManuallySelected(currentFrame) &&
        !currentAllowsSideCover &&
        !hasIntegratedFrame) {
      hasSideCovers = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      _notifyModelListeners();
      return;
    }

    final candidates = series.sections.where((section) {
      final type = section.type.toLowerCase();
      return (section.isFrame || type == 'frame' || type.contains('cadre')) &&
          _sectionAllowsStandaloneSideCover(section);
    }).toList();
    if (candidates.isEmpty) {
      hasSideCovers = false;
      useCustomSideCoverLayout = false;
      sideCoverSegments = [];
      hiddenSideCoverSegments.clear();
      _notifyModelListeners();
      return;
    }

    final target = candidates.first;
    final override = target.toMap();
    final colorId = selectedDbColor?['id'];
    if (colorId != null) {
      try {
        final price = await db.getSectionPrice(target.id, colorId);
        if (price > 0 && price != 800.0) {
          override['calculated_price'] = price;
        }
      } catch (_) {
        // The drawing can use the selected section even if a temporary local
        // price lookup fails; the next catalogue refresh will restore price.
      }
    }

    // The user may have switched to Tunnel while the price was loading.
    if (!hasShutter ||
        isCaissonTunnel ||
        series != activeFrameSeries ||
        revision != _sideCoverSelectionRevision) {
      return;
    }
    applyFrameOverride(override, sliding: usesSlidingPrimaryProfiles);
    _notifyModelListeners();
  }

  void toggleShutter(bool value) {
    if (value && hasArchOrSlant) return;
    if (hasShutter == value) return;
    _saveSnapshot();
    _applyShutterState(value);
  }

  void _applyShutterState(bool value) {
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    hasShutter = value;
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    if (!value) {
      removedShutterSides.clear();
      // The side-cover state is shared by shutter and ordinary frame views.
      // Clearing shutter-specific sides must not resurrect a bottom cover when
      // the bottom frame is absent.
      _hideBottomCoverWhenBottomFrameIsMissing();
      isCaissonTunnel = false;
    }
    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = height - oldTopOffset - (profileThickness * 2);
      double newInnerH = height - newTopOffset - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top =
              newTopOffset +
              profileThickness +
              (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
          double bottom =
              newTopOffset +
              profileThickness +
              (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            top,
            z.boundary.right,
            bottom,
          );
        }
      }
    }
    if (hasShutter) {
      updateShutterDefaultsIfNeeded();
      unawaited(_selectNonIntegratedFrameForShutter());
    }
    _notifyModelListeners();
  }

  void setShutterPosition(double val) {
    shutterPosition = val;
    _notifyModelListeners();
  }

  void toggleCaissonTunnel(bool value) {
    if (isCaissonTunnel == value) return;
    _saveSnapshot();
    double oldTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;
    isCaissonTunnel = value;
    if (isCaissonTunnel) {
      hasShutter = true;
      _synchronizeShutterMechanismValue('محرك');
      showWall = true;
      componentOverrides['الصندوق (Caisson)'] = {
        'id': -999,
        'name': 'صندوق نفق (Caisson Tunnel)',
        'price': 0.0,
        'price_dzd': 0.0,
        'component_type': 'صندوق',
        'measurement': 'tunnel',
      };
    } else {
      showWall = false;
      if (componentOverrides['الصندوق (Caisson)']?['id'] == -999) {
        componentOverrides.remove('الصندوق (Caisson)');
      }
    }
    double newTopOffset = (hasShutter && !hasArchOrSlant && !isCaissonTunnel)
        ? shutterBoxHeight
        : 0.0;

    if (zones.isNotEmpty && height > 0) {
      double oldInnerH = height - oldTopOffset - (profileThickness * 2);
      double newInnerH = height - newTopOffset - (profileThickness * 2);
      if (oldInnerH > 0 && newInnerH > 0) {
        double scaleY = newInnerH / oldInnerH;
        for (var z in zones) {
          double top =
              newTopOffset +
              profileThickness +
              (z.boundary.top - (oldTopOffset + profileThickness)) * scaleY;
          double bottom =
              newTopOffset +
              profileThickness +
              (z.boundary.bottom - (oldTopOffset + profileThickness)) * scaleY;
          z.boundary = Rect.fromLTRB(
            z.boundary.left,
            top,
            z.boundary.right,
            bottom,
          );
        }
      }
    }
    if (!isCaissonTunnel && hasShutter) {
      unawaited(_selectNonIntegratedFrameForShutter());
    }
    _notifyModelListeners();
  }

  void toggleShutterSide(String side) {
    _saveSnapshot();
    if (side == 'bottom' && !hasBottomFrame) {
      removedShutterSides.add('bottom');
      _notifyModelListeners();
      return;
    }
    if (removedShutterSides.contains(side)) {
      removedShutterSides.remove(side);
    } else {
      removedShutterSides.add(side);
    }
    _notifyModelListeners();
  }

  void prepareShutterOnlyDrawing() {
    _saveSnapshot();
    zones.clear();
    width = 0;
    height = 0;
    isShutterOnly = false;
    hasShutter = false;
    isCaissonTunnel = false;
    hasSideCovers = false;
    useCustomSideCoverLayout = false;
    sideCoverSegments = [];
    hiddenSideCoverSegments = {};
    topSlantLeftY = 0.0;
    topSlantRightY = 0.0;
    bottomSlantLeftY = 0.0;
    bottomSlantRightY = 0.0;
    archHeight = 0.0;
    _frameColor = FrameColor.white;
    final whiteColor = _defaultFrameColor();
    _selectedDbColor = whiteColor == null
        ? null
        : Map<String, dynamic>.from(whiteColor);
    _selectedAccessoryColor = null;
    mullionProfiles.clear();
    groovedMullionCavityOnPositiveSide.clear();
    mullionSectionOverrides.clear();
    primaryMullionAxis = null;
    drawNextShapeAsShutterOnly = true;
    isDrawingMode = true;
    drawingMode = 'shutter_only';
    pendingDrawStart = null;
    drawingStart = null;
    drawingCurrent = null;
    selection = SelectionInfo.none;
    activeSubZone = null;
    _notifyModelListeners();
  }

  /// Converts the current drawing into a shutter while preserving its
  /// measured size and position on the canvas.
  void convertCurrentDrawingToShutter() {
    final currentWidth = width;
    final currentHeight = height;
    if (currentWidth <= 0 || currentHeight <= 0) {
      prepareShutterOnlyDrawing();
      return;
    }

    final currentLeft = drawnLeft;
    final currentTop = drawnTop;

    // Reuse the same cleanup used when starting a new shutter drawing, then
    // restore the existing dimensions instead of asking the user to redraw.
    prepareShutterOnlyDrawing();
    width = currentWidth;
    height = currentHeight;
    drawnLeft = currentLeft;
    drawnTop = currentTop;
    isShutterOnly = true;
    hasShutter = true;
    drawNextShapeAsShutterOnly = false;
    isDrawingMode = true;
    drawingMode = 'shutter_only';
    drawingStart = null;
    drawingCurrent = null;
    pendingDrawStart = null;
    unawaited(updateShutterDefaultsIfNeeded());
    _notifyModelListeners();
  }
}
