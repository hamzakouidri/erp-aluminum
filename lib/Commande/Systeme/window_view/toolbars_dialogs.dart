part of '../show_system_francais.dart';

/// Toolbars, dialogs, menus and shortcuts of the drawing page.
extension _WindowViewToolbars on _WindowViewState {
  void _showShortcutFeedback(String message, {IconData? icon, Color? color}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (icon != null) ...[
              Icon(icon, color: Colors.white, size: 20),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
        backgroundColor: color ?? Colors.blueGrey.shade800,
        duration: const Duration(milliseconds: 1400),
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.only(bottom: 60, left: 24, right: 24),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
    );
  }

  void _toggleWallFeature() {
    final newVal = !widget.model.showWall;
    widget.model.toggleShowWall(newVal);
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _showShortcutFeedback(
      Localization.translate(
        newVal ? 'تم تفعيل الحائط' : 'تم إلغاء الحائط',
        lang,
      ),
      icon: Icons.wallpaper_rounded,
      color: newVal ? Colors.teal.shade700 : Colors.red.shade700,
    );
    _setViewState(() {});
  }

  Future<void> _toggleSideCoversFeature() async {
    final zone = widget.model.selectedZone;
    final bool isNestedSlidingFrame =
        zone != null && widget.model.isSlidingZoneNestedInSingleFrame(zone);
    if (isNestedSlidingFrame) {
      final newVal = !widget.model.hasInternalSlidingSideCover;
      widget.model.toggleInternalSlidingSideCover(newVal);
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      _showShortcutFeedback(
        Localization.translate(
          newVal
              ? 'تمت إضافة غطاء الإطار المنزلق'
              : 'تمت إزالة غطاء الإطار المنزلق',
          lang,
        ),
        icon: Icons.border_outer_rounded,
        color: newVal ? Colors.amber.shade800 : Colors.red.shade700,
      );
    } else {
      final newVal = !widget.model.hasSideCovers;
      if (_refuseSideCoverOnNotch(newVal)) return;
      await widget.model.toggleSideCovers(newVal);
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      _showShortcutFeedback(
        Localization.translate(
          newVal ? 'تمت إضافة الغطاء الجانبي' : 'تمت إزالة الغطاء الجانبي',
          lang,
        ),
        icon: Icons.border_outer_rounded,
        color: newVal ? Colors.amber.shade800 : Colors.red.shade700,
      );
    }
    if (mounted) _setViewState(() {});
  }

  void _toggleViewModeFeature() {
    widget.model.toggleViewMode();
    final isInternal = widget.model.isInternalView;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _showShortcutFeedback(
      isInternal
          ? Localization.translate('مشاهدة: وجه داخلي', lang)
          : Localization.translate('مشاهدة: وجه خارجي', lang),
      icon: isInternal ? Icons.visibility : Icons.flip_camera_android,
      color: isInternal ? Colors.blue.shade700 : Colors.orange.shade800,
    );
    _setViewState(() {});
  }

  void _toggleBottomFrameFeature() {
    if (!widget.model.canEditSelectedBottomFrame) return;
    final newVal = !widget.model.selectedFrameHasBottom;
    widget.model.toggleBottomFrame(newVal);
    _showShortcutFeedback(
      newVal ? 'تم تفعيل الإطار السفلي (Cadre bas)' : 'تم إلغاء الإطار السفلي',
      icon: Icons.border_bottom_rounded,
      color: newVal ? Colors.teal.shade700 : Colors.red.shade700,
    );
    _setViewState(() {});
  }

  void _toggleRightDrawerFeature() {
    _setViewState(() => _isDrawerOpen = !_isDrawerOpen);
    _showShortcutFeedback(
      _isDrawerOpen ? 'تم فتح لوحة الخصائص' : 'تم إغلاق لوحة الخصائص',
      icon: Icons.tune_rounded,
      color: Colors.blue.shade700,
    );
  }

  Widget _buildQuickCanvasPill({
    required BuildContext context,
    required String label,
    required IconData icon,
    required bool isActive,
    required Color activeColor,
    required VoidCallback onTap,
    String? tooltip,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isActive
        ? (isDark
              ? activeColor.withValues(alpha: 0.3)
              : activeColor.withValues(alpha: 0.12))
        : (isDark ? const Color(0xFF2A2A3C) : Colors.white);
    final borderColor = isActive
        ? activeColor
        : (isDark ? Colors.white12 : Colors.grey.shade300);
    final fg = isActive
        ? activeColor
        : (isDark ? Colors.white70 : Colors.grey.shade800);

    final pill = Material(
      elevation: 2,
      color: bg,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: borderColor, width: isActive ? 1.5 : 1.0),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 16, color: fg),
              const SizedBox(width: 5),
              Text(
                label,
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  fontWeight: isActive ? FontWeight.bold : FontWeight.w600,
                  color: fg,
                ),
              ),
            ],
          ),
        ),
      ),
    );

    if (tooltip != null) {
      return Tooltip(
        message: tooltip,
        waitDuration: const Duration(milliseconds: 300),
        child: pill,
      );
    }
    return pill;
  }

  Widget _buildQuickActionsBar(
    BuildContext context, {
    required bool isVertical,
  }) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isTabletOrDesktop =
        _isWindowsDesktop || MediaQuery.sizeOf(context).width >= 600;

    final items = <Widget>[
      if (isTabletOrDesktop) ...[
        // زر الحائط
        _buildQuickCanvasPill(
          context: context,
          label: Localization.translate('حائط', lang),
          icon: Icons.wallpaper_rounded,
          isActive: widget.model.showWall,
          activeColor: Colors.teal.shade700,
          tooltip: Localization.translate('تفعيل أو إلغاء الحائط', lang),
          onTap: _toggleWallFeature,
        ),
        // زر الستار
        _buildQuickCanvasPill(
          context: context,
          label: Localization.translate('ستار', lang),
          icon: widget.model.hasShutter
              ? Icons.layers_rounded
              : Icons.layers_outlined,
          isActive: widget.model.hasShutter,
          activeColor: Colors.blue.shade700,
          tooltip: Localization.translate(
            'تفعيل أو إلغاء الستار على النافذة',
            lang,
          ),
          onTap: _toggleShutterFeature,
        ),
        // Pricing-only mosquito screen. It must not alter the drawing.
        _buildQuickCanvasPill(
          context: context,
          label: Localization.translate('موستيكير', lang),
          icon: Icons.grid_on_rounded,
          isActive: widget.model.hasMoustiquaireAddon,
          activeColor: Colors.green.shade700,
          tooltip: Localization.translate(
            'إضافتها إلى الكمية والتكلفة دون إظهارها في الرسم',
            lang,
          ),
          onTap: _toggleMoustiquaireAddon,
        ),
        // زر صندوق النفق
        _buildQuickCanvasPill(
          context: context,
          label: Localization.translate('نفق', lang),
          icon: Icons.horizontal_rule_rounded,
          isActive: widget.model.isCaissonTunnel,
          activeColor: Colors.deepPurple.shade700,
          tooltip: Localization.translate('تفعيل أو إلغاء صندوق النفق', lang),
          onTap: _toggleCaissonTunnelFeature,
        ),
        // زر الغطاء الجانبي
        _buildQuickCanvasPill(
          context: context,
          label: Localization.translate('غطاء جانبي', lang),
          icon: Icons.border_outer_rounded,
          isActive:
              widget.model.hasSideCovers ||
              widget.model.hasInternalSlidingSideCover,
          activeColor: Colors.amber.shade800,
          tooltip: Localization.translate(
            'تفعيل أو إلغاء الغطاء الجانبي',
            lang,
          ),
          onTap: () => unawaited(_toggleSideCoversFeature()),
        ),
        // زر جهة العرض: داخلي / خارجي
        _buildQuickCanvasPill(
          context: context,
          label: widget.model.isInternalView
              ? Localization.translate('وجه داخلي', lang)
              : Localization.translate('وجه خارجي', lang),
          icon: widget.model.isInternalView
              ? Icons.visibility
              : Icons.flip_camera_android,
          isActive: true,
          activeColor: widget.model.isInternalView
              ? Colors.blue.shade700
              : Colors.orange.shade800,
          tooltip: Localization.translate('تبديل جهة عرض النافذة', lang),
          onTap: _toggleViewModeFeature,
        ),
        // زر إطار سفلي
        if (widget.model.systemMode != 'sliding')
          _buildQuickCanvasPill(
            context: context,
            label: Localization.translate('إطار سفلي', lang),
            icon: Icons.border_bottom_rounded,
            isActive: widget.model.selectedFrameHasBottom,
            activeColor: Colors.teal.shade700,
            tooltip: Localization.translate(
              'تفعيل أو إلغاء الإطار السفلي',
              lang,
            ),
            onTap: _toggleBottomFrameFeature,
          ),
        if (widget.model.hasShutter) ...[
          // آلية الستار (محرك / مانيفيل / حزام)
          _buildQuickCanvasPill(
            context: context,
            label: switch (widget.model.shutterMechanism) {
              'محرك' => Localization.translate('محرك', lang),
              'منايفال' => Localization.translate('منايفال', lang),
              _ => Localization.translate('حزام', lang),
            },
            icon: widget.model.shutterMechanism == 'محرك'
                ? Icons.electrical_services_rounded
                : (widget.model.shutterMechanism == 'منايفال'
                      ? Icons.rotate_right_rounded
                      : Icons.line_weight_rounded),
            isActive: true,
            activeColor: Colors.indigo.shade600,
            tooltip: Localization.translate(
              'تبديل آلية الستار: محرك / منايفال / حزام',
              lang,
            ),
            onTap: _cycleShutterMechanismFeature,
          ),
          // جهة الستار (يمين / يسار)
          _buildQuickCanvasPill(
            context: context,
            label: widget.model.shutterDriveSide == 'right'
                ? Localization.translate('يمين', lang)
                : Localization.translate('يسار', lang),
            icon: widget.model.shutterDriveSide == 'right'
                ? Icons.keyboard_double_arrow_right_rounded
                : Icons.keyboard_double_arrow_left_rounded,
            isActive: true,
            activeColor: Colors.blueGrey.shade700,
            tooltip: Localization.translate(
              'تبديل جهة الستار: يمين / يسار',
              lang,
            ),
            onTap: () => _toggleShutterDriveSideFeature(),
          ),
        ],
      ],
      // زر الخصائص (فتح لوحة الدرج الأيمن)
      _buildQuickCanvasPill(
        context: context,
        label: Localization.translate('الخصائص', lang),
        icon: Icons.tune_rounded,
        isActive: _isDrawerOpen,
        activeColor: Colors.indigo.shade700,
        tooltip: Localization.translate('فتح لوحة الخصائص', lang),
        onTap: _toggleRightDrawerFeature,
      ),
    ];

    if (isVertical) {
      return SingleChildScrollView(
        scrollDirection: Axis.vertical,
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              items[i],
            ],
          ],
        ),
      );
    }

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < items.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            items[i],
          ],
        ],
      ),
    );
  }

  bool _drawingShortcut(KeyEvent event) {
    if (!mounted ||
        !_isWindowsDesktop ||
        event is! KeyDownEvent ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null) {
      if ((focus.widget is EditableText) ||
          focus.findAncestorWidgetOfExactType<EditableText>() != null) {
        return false;
      }
    }

    final isCtrl =
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed;
    final isAlt = HardwareKeyboard.instance.isAltPressed;
    final key = event.logicalKey;
    final char = event.character?.toLowerCase();

    // 1. Tab switches with Alt modifier:
    // Alt + C: Communs tab (0)
    if (isAlt &&
        (key == LogicalKeyboardKey.keyC || char == 'c' || char == 'ؤ')) {
      _switchToBottomTab(0);
      _showShortcutFeedback(
        'القائمة السفلية: المشترك (Communs)',
        icon: Icons.tune_rounded,
      );
      return true;
    }

    // Alt + D / F / E: Dormant tab (1)
    if (isAlt &&
        (key == LogicalKeyboardKey.keyE ||
            key == LogicalKeyboardKey.keyF ||
            key == LogicalKeyboardKey.keyD ||
            char == 'e' ||
            char == 'f' ||
            char == 'd' ||
            char == 'ث' ||
            char == 'ب' ||
            char == 'ي')) {
      _switchToBottomTab(1);
      _showShortcutFeedback(
        'القائمة السفلية: الإطار (Dormant)',
        icon: Icons.border_outer_rounded,
      );
      return true;
    }

    // Alt + O / L: Ouvrant tab (2)
    if (isAlt &&
        (key == LogicalKeyboardKey.keyO ||
            key == LogicalKeyboardKey.keyL ||
            char == 'o' ||
            char == 'l' ||
            char == 'خ' ||
            char == 'م')) {
      _switchToBottomTab(2);
      _showShortcutFeedback(
        'القائمة السفلية: الظلفة (Ouvrant)',
        icon: Icons.door_back_door_rounded,
      );
      return true;
    }

    // 2. M for Wall (الحائط): toggle on/off
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyM ||
            char == 'm' ||
            char == 'ة' ||
            char == 'م')) {
      _toggleWallFeature();
      return true;
    }

    // 3. V for Shutter (الستار): toggle on/off
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyV || char == 'v' || char == 'ر')) {
      _toggleShutterFeature();
      return true;
    }

    // 4. C for Side Covers (الغطاء الجانبي Caches): toggle on/off
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyC ||
            char == 'c' ||
            char == 'ؤ' ||
            (isCtrl &&
                (key == LogicalKeyboardKey.keyG ||
                    key == LogicalKeyboardKey.keyJ ||
                    char == 'g' ||
                    char == 'j')))) {
      unawaited(_toggleSideCoversFeature());
      return true;
    }

    // 5. T for Tunnel Box (صندوق النفق Caisson Tunnel): toggle on/off
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyT || char == 't' || char == 'ف')) {
      _toggleCaissonTunnelFeature();
      return true;
    }

    // 6. I for View Mode (الوجه الداخلي / الخارجي): toggle
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyI || char == 'i' || char == 'ه')) {
      _toggleViewModeFeature();
      return true;
    }

    // 7. B for Bottom Frame (الإطار السفلي Dormant bas): toggle on/off
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyB || char == 'b' || char == 'لا')) {
      _toggleBottomFrameFeature();
      return true;
    }

    // 8. D for Drawer (لوحة الخصائص): toggle
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyD || char == 'd' || char == 'ي')) {
      _toggleRightDrawerFeature();
      return true;
    }

    // 9. Shutter Mechanism (محرك / مانيفيل / حزام):
    // مفتاح K (أو ن في لوحة المفاتيح العربية)
    if (!isAlt &&
        (key == LogicalKeyboardKey.keyK ||
            char == 'k' ||
            char == 'ن' ||
            (isCtrl && key == LogicalKeyboardKey.keyK))) {
      _cycleShutterMechanismFeature();
      return true;
    }

    // 10. Shutter Drive Side (جهة الستار: يمين / يسار)
    // يمين: السهم الأيمن أو R أو Ctrl+Right أو Ctrl+R
    if (key == LogicalKeyboardKey.arrowRight ||
        (isCtrl &&
            (key == LogicalKeyboardKey.keyR ||
                key == LogicalKeyboardKey.keyS ||
                char == 'r' ||
                char == 's')) ||
        (!isAlt &&
            !isCtrl &&
            (key == LogicalKeyboardKey.keyR || char == 'r' || char == 'ق'))) {
      _toggleShutterDriveSideFeature('right');
      return true;
    }

    // يسار: السهم الأيسر أو Ctrl+Left أو Ctrl+L
    if (key == LogicalKeyboardKey.arrowLeft ||
        (isCtrl && (key == LogicalKeyboardKey.keyL || char == 'l'))) {
      _toggleShutterDriveSideFeature('left');
      return true;
    }

    // 11. Toggle drawing mode if matches registered shortcut
    if (ShortcutBindings.instance.matches('drawing_mode', event)) {
      _toggleDrawingInteractionMode();
      return true;
    }

    return false;
  }

  void _showMullionResizeDialog(BuildContext context, int section) {
    bool isH = widget.model.selection.isHorizontalMullion!;
    double pos = widget.model.selection.mullionPosition!;
    final t = widget.model.profileThickness;
    // Same separator as resizeMullionDimension: a coupled-frame joint is two
    // frame bars wide, not one mullion, otherwise the shown clear size and
    // the applied one disagree.
    final sep = widget.model.isDoubleFrameMullionAt(isH, pos)
        ? widget.model.frameProfileWidthAt(isH, pos)
        : widget.model.mullionThickness / 2;
    final inset = t + sep;
    double valueAt(double position) => isH
        ? (section == 1
              ? (position - inset)
              : (widget.model.height - position - inset))
        : (section == 1
              ? (position - inset)
              : (widget.model.width - position - inset));
    double currentValue = valueAt(pos);
    final ctrl = TextEditingController(text: currentValue.toInt().toString());
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        String label = isH
            ? (section == 1
                  ? 'تعديل الفراغ العلوي (mm)'
                  : 'تعديل الفراغ السفلي (mm)')
            : (section == 1
                  ? 'تعديل الفراغ الأيسر (mm)'
                  : 'تعديل الفراغ الأيمن (mm)');
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate(label, lang),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate(
                'البُعد الصافي للفراغ (mm)',
                lang,
              ),
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.grey.shade700 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val == null || val <= 0) {
                  _acceptDimension(null, 1, isH ? widget.model.height : widget.model.width);
                  return;
                }
                  widget.model.resizeMullionDimension(section, val);
                // The model keeps every neighbouring zone above its minimum;
                // tell the user when the typed size had to be adjusted.
                final applied = widget.model.selection.mullionPosition;
                if (applied != null && (valueAt(applied) - val).abs() > 1.0) {
                  ScaffoldMessenger.of(this.context).showSnackBar(
                    SnackBar(
                      content: Text(
                        _tr('تم ضبط القياس إلى {value} مم ليبقى كل جزء ضمن الحد الأدنى')
                            .replaceAll(
                              '{value}',
                              valueAt(applied).round().toString(),
                            ),
                      ),
                      backgroundColor: Colors.orange.shade800,
                    ),
                  );
                }
                Navigator.pop(context);
              },
              child: Text(
                Localization.translate('تطبيق القياس الجديد', lang),
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  List<Widget> _buildWindowsAppBarDrawingControls(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final foreground = isDark ? Colors.blue.shade200 : Colors.blue.shade900;
    final buttonStyle = TextButton.styleFrom(
      foregroundColor: foreground,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      visualDensity: VisualDensity.compact,
    );

    IconButton iconButton({
      required IconData icon,
      required String tooltip,
      required VoidCallback onPressed,
    }) {
      return IconButton(
        icon: Icon(icon, size: 20),
        tooltip: tooltip,
        color: foreground,
        visualDensity: VisualDensity.compact,
        onPressed: onPressed,
      );
    }

    return [
      const SizedBox(width: 8),
      TextButton.icon(
        style: buttonStyle,
        onPressed: () => _showResizeDialog(context, focusWidth: true),
        icon: const Icon(Icons.straighten_rounded, size: 18),
        label: Text(
          '${widget.model.width.toInt()} × ${widget.model.height.toInt()}',
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      // Design mode edits the drawing; move mode only pans and zooms. On
      // Windows design is the default and stays on until switched.
      TextButton.icon(
        style: widget.model.isDrawingMode
            ? buttonStyle.copyWith(
                backgroundColor: WidgetStatePropertyAll(Colors.green.shade600),
                foregroundColor: const WidgetStatePropertyAll(Colors.white),
              )
            : buttonStyle,
        onPressed: _toggleDrawingInteractionMode,
        icon: Icon(
          widget.model.isDrawingMode
              ? Icons.draw_rounded
              : Icons.pan_tool_alt_rounded,
          size: 18,
        ),
        label: Text(
          widget.model.isDrawingMode
              ? Localization.translate('وضع الرسم', lang)
              : Localization.translate('وضع التحريك', lang),
          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
        ),
      ),
      TextButton.icon(
        style: buttonStyle,
        onPressed: _activateShutterFromDesign,
        icon: Icon(
          widget.model.hasShutter
              ? Icons.layers_rounded
              : Icons.add_box_rounded,
          size: 18,
          color: widget.model.hasShutter ? Colors.orange.shade700 : null,
        ),
        label: Text(
          Localization.translate('ستار', lang),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: widget.model.hasShutter ? Colors.orange.shade700 : null,
          ),
        ),
      ),
      if (widget.model.hasShutter)
        TextButton.icon(
          style: buttonStyle,
          onPressed: () => _showSplitShutterDialog(context),
          icon: Icon(
            Icons.view_column_rounded,
            size: 18,
            color: widget.model.isShutterSplit ? Colors.teal.shade700 : null,
          ),
          label: Text(
            widget.model.isShutterSplit
                ? '${Localization.translate('فصل الصناديق', lang)} (${widget.model.effectiveShutterSplits.length})'
                : Localization.translate('فصل الصناديق', lang),
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.bold,
              color: widget.model.isShutterSplit ? Colors.teal.shade700 : null,
            ),
          ),
        ),
      iconButton(
        icon: Icons.center_focus_strong_outlined,
        tooltip: Localization.translate('توسيط الرسم', lang),
        onPressed: _resetDrawingZoom,
      ),
      iconButton(
        icon: Icons.remove,
        tooltip: Localization.translate('تصغير الرسم', lang),
        onPressed: () =>
            _changeDrawingZoom(1 / _WindowViewState._zoomStep, _drawingViewportCenter()),
      ),
      iconButton(
        icon: Icons.add,
        tooltip: Localization.translate('تكبير الرسم', lang),
        onPressed: () =>
            _changeDrawingZoom(_WindowViewState._zoomStep, _drawingViewportCenter()),
      ),
    ];
  }

  void _showInnerResizeDialog(BuildContext context, InnerDimensionHit hit) {
    // تم إزالة قفل الارتفاع لتتمكن من تعديل الطول والعرض براحتك
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    double currentValue = 0;
    String title = '';

    if (hit.isSashDivision) {
      final isRight = hit.isDoubleSashRight;
      final sashT =
          zone.sashThickness ??
          widget.model.getSectionThickness('sash', fallback: 45.0);
      final dividerT = widget.model.getSectionThickness(
        'mullion',
        fallback: sashT,
      );
      Rect parentR = zone.boundary;
      Rect sashR = parentR;
      if (zone.content == ZoneContent.doubleSash) {
        final sep = 4.0;
        final midX = parentR.left + parentR.width * zone.doubleSashRatio;
        if (!isRight) {
          sashR = Rect.fromLTRB(
            parentR.left,
            parentR.top,
            midX - sep / 2,
            parentR.bottom,
          );
        } else {
          sashR = Rect.fromLTRB(
            midX + sep / 2,
            parentR.top,
            parentR.right,
            parentR.bottom,
          );
        }
      }
      final glassR = widget.model.getSafeGlassRect(sashR, sashT);

      final hPositions = isRight
          ? zone.rightInnerHPositions
          : zone.innerHPositions;
      final vPositions = isRight
          ? zone.rightInnerVPositions
          : zone.innerVPositions;
      final innerH = isRight ? zone.rightInnerH : zone.innerH;
      final innerV = isRight ? zone.rightInnerV : zone.innerV;

      List<double> finalHPos = List.from(hPositions);
      if (finalHPos.isEmpty && innerH > 0) {
        double stepY = 1.0 / (innerH + 1);
        for (int i = 1; i <= innerH; i++) {
          finalHPos.add(stepY * i);
        }
      }
      List<double> finalVPos = List.from(vPositions);
      if (finalVPos.isEmpty && innerV > 0) {
        double stepX = 1.0 / (innerV + 1);
        for (int i = 1; i <= innerV; i++) {
          finalVPos.add(stepX * i);
        }
      }

      if (hit.isWidth) {
        int cols = finalVPos.length + 1;
        int col = hit.divisionIndex;
        double leftRatio = col == 0 ? 0.0 : finalVPos[col - 1];
        double rightRatio = col == cols - 1 ? 1.0 : finalVPos[col];
        double left = glassR.left + (glassR.width * leftRatio);
        if (col > 0) left += dividerT / 2;
        double right = glassR.left + (glassR.width * rightRatio);
        if (col < cols - 1) right -= dividerT / 2;
        currentValue = right - left;
        title = 'تعديل عرض الخلية الداخلية';
      } else {
        int rows = finalHPos.length + 1;
        int row = hit.divisionIndex;
        double topRatio = row == 0 ? 0.0 : finalHPos[row - 1];
        double bottomRatio = row == rows - 1 ? 1.0 : finalHPos[row];
        double top = glassR.top + (glassR.height * topRatio);
        if (row > 0) top += dividerT / 2;
        double bottom = glassR.top + (glassR.height * bottomRatio);
        if (row < rows - 1) bottom -= dividerT / 2;
        currentValue = bottom - top;
        title = 'تعديل ارتفاع الخلية الداخلية';
      }
    } else if (hit.isDoubleSashLeft) {
      final effectiveRatio = widget.model.isInternalView
          ? zone.doubleSashRatio
          : 1.0 - zone.doubleSashRatio;
      currentValue = _shownDoubleSashCuttingWidth(zone, effectiveRatio);
      title = 'تعديل عرض الدلفة اليسرى';
    } else if (hit.isDoubleSashRight) {
      final effectiveRatio = widget.model.isInternalView
          ? zone.doubleSashRatio
          : 1.0 - zone.doubleSashRatio;
      currentValue = _shownDoubleSashCuttingWidth(zone, 1.0 - effectiveRatio);
      title = 'تعديل عرض الدلفة اليمنى';
    } else {
      currentValue = hit.isWidth ? zone.boundary.width : zone.boundary.height;
      title = hit.isWidth ? 'تعديل عرض التقسيم' : 'تعديل ارتفاع التقسيم';
    }

    final ctrl = TextEditingController(text: _shownDimensionText(currentValue));
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    showDialog(
      context: context,
      builder: (context) {
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate(title, lang),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate('القياس الداخلي (mm)', lang),
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.white70 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text.replaceAll(',', '.'));
                if (val != null) {
                  if (hit.isSashDivision) {
                    {
                      final isRight = hit.isDoubleSashRight;
                      final sashT =
                          zone.sashThickness ??
                          widget.model.getSectionThickness(
                            'sash',
                            fallback: 45.0,
                          );
                      final dividerT = widget.model.getSectionThickness(
                        'mullion',
                        fallback: sashT,
                      );
                      Rect parentR = zone.boundary;
                      Rect sashR = parentR;
                      if (zone.content == ZoneContent.doubleSash) {
                        final sep = 4.0;
                        final midX =
                            parentR.left + parentR.width * zone.doubleSashRatio;
                        if (!isRight) {
                          sashR = Rect.fromLTRB(
                            parentR.left,
                            parentR.top,
                            midX - sep / 2,
                            parentR.bottom,
                          );
                        } else {
                          sashR = Rect.fromLTRB(
                            midX + sep / 2,
                            parentR.top,
                            parentR.right,
                            parentR.bottom,
                          );
                        }
                      }
                      final glassR = widget.model.getSafeGlassRect(
                        sashR,
                        sashT,
                      );

                      final hPositions = isRight
                          ? zone.rightInnerHPositions
                          : zone.innerHPositions;
                      final vPositions = isRight
                          ? zone.rightInnerVPositions
                          : zone.innerVPositions;
                      final innerH = isRight ? zone.rightInnerH : zone.innerH;
                      final innerV = isRight ? zone.rightInnerV : zone.innerV;

                      List<double> finalHPos = List.from(hPositions);
                      if (finalHPos.isEmpty && innerH > 0) {
                        for (int i = 1; i <= innerH; i++) {
                          finalHPos.add((1.0 / (innerH + 1)) * i);
                        }
                      }
                      List<double> finalVPos = List.from(vPositions);
                      if (finalVPos.isEmpty && innerV > 0) {
                        for (int i = 1; i <= innerV; i++) {
                          finalVPos.add((1.0 / (innerV + 1)) * i);
                        }
                      }

                      // Each cell keeps 80 mm of clear glass between
                      // divisions; the neighbouring cell gives or takes the
                      // difference, so the cells still add up to the leaf.
                      final axisPositions = hit.isWidth ? finalVPos : finalHPos;
                      final glassLength = hit.isWidth
                          ? glassR.width
                          : glassR.height;
                      final cellCount = axisPositions.length + 1;
                      double cellSize(int i) {
                        final start = i == 0 ? 0.0 : axisPositions[i - 1];
                        final end = i == cellCount - 1
                            ? 1.0
                            : axisPositions[i];
                        return (end - start) * glassLength -
                            (i > 0 ? dividerT / 2 : 0) -
                            (i < cellCount - 1 ? dividerT / 2 : 0);
                      }

                      final cell = hit.divisionIndex.clamp(0, cellCount - 1);
                      final neighbour = cell < cellCount - 1
                          ? cell + 1
                          : cell - 1;
                      final maxCell = neighbour < 0
                          ? cellSize(cell)
                          : cellSize(cell) +
                                cellSize(neighbour) -
                                WindowModel.minimumSashCellMm;
                      if (!_acceptDimension(
                        val,
                        WindowModel.minimumSashCellMm,
                        maxCell,
                      )) {
                        return;
                      }

                      if (hit.isWidth) {
                        int cols = finalVPos.length + 1;
                        int col = hit.divisionIndex;
                        if (col < cols - 1) {
                          double leftRatio = col == 0
                              ? 0.0
                              : finalVPos[col - 1];
                          double left =
                              glassR.left + (glassR.width * leftRatio);
                          double leftAdjusted =
                              left + (col > 0 ? dividerT / 2 : 0);
                          double rightAdjusted = leftAdjusted + val;
                          double right =
                              rightAdjusted +
                              (col < cols - 1 ? dividerT / 2 : 0);
                          double newRightRatio =
                              ((right - glassR.left) / glassR.width).clamp(
                                0.05,
                                0.95,
                              );
                          widget.model.updateZoneInnerVDivisionRatio(
                            hit.zoneId,
                            isRight,
                            col,
                            newRightRatio,
                          );
                        } else if (col > 0) {
                          double rightRatio = 1.0;
                          double right =
                              glassR.left + (glassR.width * rightRatio);
                          double rightAdjusted =
                              right - (col < cols - 1 ? dividerT / 2 : 0);
                          double leftAdjusted = rightAdjusted - val;
                          double leftNew =
                              leftAdjusted - (col > 0 ? dividerT / 2 : 0);
                          double newLeftRatio =
                              ((leftNew - glassR.left) / glassR.width).clamp(
                                0.05,
                                0.95,
                              );
                          widget.model.updateZoneInnerVDivisionRatio(
                            hit.zoneId,
                            isRight,
                            col - 1,
                            newLeftRatio,
                          );
                        }
                      } else {
                        int rows = finalHPos.length + 1;
                        int row = hit.divisionIndex;
                        if (row < rows - 1) {
                          double topRatio = row == 0 ? 0.0 : finalHPos[row - 1];
                          double top = glassR.top + (glassR.height * topRatio);
                          double topAdjusted =
                              top + (row > 0 ? dividerT / 2 : 0);
                          double bottomAdjusted = topAdjusted + val;
                          double bottom =
                              bottomAdjusted +
                              (row < rows - 1 ? dividerT / 2 : 0);
                          double newBottomRatio =
                              ((bottom - glassR.top) / glassR.height).clamp(
                                0.05,
                                0.95,
                              );
                          widget.model.updateZoneInnerHDivisionRatio(
                            hit.zoneId,
                            isRight,
                            row,
                            newBottomRatio,
                          );
                        } else if (row > 0) {
                          double bottomRatio = 1.0;
                          double bottom =
                              glassR.top + (glassR.height * bottomRatio);
                          double bottomAdjusted =
                              bottom - (row < rows - 1 ? dividerT / 2 : 0);
                          double topAdjusted = bottomAdjusted - val;
                          double topNew =
                              topAdjusted - (row > 0 ? dividerT / 2 : 0);
                          double newTopRatio =
                              ((topNew - glassR.top) / glassR.height).clamp(
                                0.05,
                                0.95,
                              );
                          widget.model.updateZoneInnerHDivisionRatio(
                            hit.zoneId,
                            isRight,
                            row - 1,
                            newTopRatio,
                          );
                        }
                      }
                    }
                  } else if (hit.isDoubleSashLeft || hit.isDoubleSashRight) {
                    // Each leaf keeps 15–85 % of the leaves' cutting width;
                    // the other leaf takes the rest so the sum stays equal.
                    if (!_acceptDimension(
                      val,
                      _shownDoubleSashCuttingWidth(zone, 0.15),
                      _shownDoubleSashCuttingWidth(zone, 0.85),
                    )) {
                      return;
                    }
                    final leafRatio = _visualRatioForLeftLeafCut(zone, val);
                    final visualLeftRatio =
                        (hit.isDoubleSashLeft ? leafRatio : 1.0 - leafRatio)
                            .clamp(0.15, 0.85)
                            .toDouble();
                    widget.model.updateZoneDoubleSashRatio(
                      hit.zoneId,
                      _storedDoubleSashRatio(visualLeftRatio),
                    );
                  } else {
                    // The neighbour gives or takes the difference, so the
                    // parts always add up to the frame's clear size.
                    final limits = widget.model.innerSizeLimits(
                      hit.zoneId,
                      hit.isWidth,
                    );
                    if (limits == null) {
                      ScaffoldMessenger.of(this.context).showSnackBar(
                        SnackBar(
                          content: Text(
                            _tr('هذا الجزء غير مقسّم: غيّر القياس الخارجي للإطار'),
                          ),
                          backgroundColor: Colors.orange.shade800,
                        ),
                      );
                    } else if (!_acceptDimension(
                      val,
                      limits.min,
                      limits.max,
                    )) {
                      return;
                  } else {
                      widget.model.resizeZoneInner(
                        hit.zoneId,
                        hit.isWidth,
                        val,
                      );
                    }
                  }
                } else {
                  _acceptDimension(null, 1, double.infinity);
                  return;
                }
                Navigator.pop(context);
              },
              child: Text(
                Localization.translate('تطبيق', lang),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  /// Shows outer-dimension dialog for a single frame in a coupled window.
  void _showFrameResizeDialog(BuildContext context, InnerDimensionHit hit) {
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    final double pt = widget.model.profileThickness;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    double outerVal;
    String title;
    if (hit.isWidth) {
      outerVal =
          widget.model.frameRectForZone(hit.zoneId)?.width ??
          zone.boundary.width + 2 * pt;
      title = 'تعديل عرض الإطار (خارجي)';
    } else {
      outerVal =
          widget.model.frameRectForZone(hit.zoneId)?.height ??
          zone.boundary.height + 2 * pt;
      title = 'تعديل ارتفاع الإطار (خارجي)';
    }
    final ctrl = TextEditingController(text: outerVal.toInt().toString());
    showDialog(
      context: context,
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate(title, lang),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
            decoration: InputDecoration(
              labelText: Localization.translate(
                hit.isWidth ? 'العرض الخارجي (mm)' : 'الارتفاع الخارجي (mm)',
                lang,
              ),
              labelStyle: TextStyle(
                color: isDark ? Colors.white70 : Colors.black87,
              ),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(
                  color: isDark ? Colors.white70 : Colors.blueGrey,
                ),
              ),
              focusedBorder: const OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                // Same range the model enforces: 380 mm (250 mm beside a
                // side of one metre or more) up to one bar length.
                final limits = widget.model.frameOuterLimits(
                  hit.zoneId,
                  isWidth: hit.isWidth,
                );
                if (!_acceptDimension(val, limits.min, limits.max)) {
                  return;
                }
                if (val != null) {
                  widget.model.resizeFrameOuterDimensionForZone(
                    hit.zoneId,
                    isWidth: hit.isWidth,
                    outerSize: val,
                  );
                }
                Navigator.pop(ctx);
              },
              child: Text(
                Localization.translate('تطبيق', lang),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showDesktopContextMenu(
    BuildContext context,
    Offset globalPosition,
    Offset localPosition,
  ) async {
    if (_isContextMenuOpen) return;
    final modelPos = _getModelPos(localPosition);

    // 1. Check if shutter is clicked
    if (widget.model.hasShutter) {
      final double shutterTop = -widget.model.shutterBoxHeight;
      final double shutterBottom = widget.model.topSlantLeftY;
      if (modelPos.dy >= shutterTop - 20 &&
          modelPos.dy <= shutterBottom + 10 &&
          modelPos.dx >= -20 &&
          modelPos.dx <= widget.model.width + 20) {
        _setViewState(() {
          _isShutterSelected = true;
          _activeShutterTab = 0;
          widget.model.clearSelection();
        });
      }
    }

    final frameAtBorder = _frameAtBorder(modelPos);
    if (frameAtBorder != null) {
      _setViewState(() {
        _isShutterSelected = false;
      });
      widget.model.selectFrameByIndex(frameAtBorder);
    } else if (!_isShutterSelected) {
      _setViewState(() {
        _isShutterSelected = false;
      });
      widget.model.selectAt(modelPos, isLongPress: false);
    }

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final selectedZone = widget.model.selectedZone;
    final isFrame = widget.model.selection.type == SelectionType.frame;

    final menuItems = <PopupMenuEntry<String>>[
      PopupMenuItem<String>(
        enabled: false,
        height: 32,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              _isShutterSelected
                  ? Icons.menu_rounded
                  : (isFrame
                        ? Icons.crop_square_rounded
                        : Icons.window_rounded),
              size: 16,
              color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
            ),
            const SizedBox(width: 8),
            Text(
              _isShutterSelected
                  ? 'خصائص الستار'
                  : (isFrame ? 'خصائص الإطار' : 'خصائص المنطقة والضلفة'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isDark ? Colors.white70 : Colors.black87,
              ),
            ),
          ],
        ),
      ),
      const PopupMenuDivider(height: 1),

      if (selectedZone != null && !_isShutterSelected && !isFrame) ...[
        _buildContextMenuItem(
          value: 'content_fixe',
          icon: Icons.crop_landscape_rounded,
          label: 'زجاج ثابت (Fixe)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_single_sash',
          icon: Icons.sensor_door_outlined,
          label: 'ضلفة عادية (Ouvrant Simple)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_double_sash',
          icon: Icons.door_sliding_outlined,
          label: 'ضلفة فرنسية مزدوجة (Double Ouvrant)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_sliding_2',
          icon: Icons.compare_arrows_rounded,
          label: 'منزلق 2 ضلف (Coulissant 2 Vantaux)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_sliding_3',
          icon: Icons.view_column_rounded,
          label: 'منزلق 3 ضلف (Coulissant 3 Vantaux)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_sliding_4',
          icon: Icons.grid_view_rounded,
          label: 'منزلق 4 ضلف (Coulissant 4 Vantaux)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'content_vide',
          icon: Icons.check_box_outline_blank_rounded,
          label: 'تفريغ (Vide)',
          isDark: isDark,
        ),
        const PopupMenuDivider(height: 1),
        _buildContextMenuItem(
          value: 'add_h_division',
          icon: Icons.border_horizontal_rounded,
          label: 'إضافة قاطع أفقي (+ Traverse)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'add_v_division',
          icon: Icons.border_vertical_rounded,
          label: 'إضافة قاطع عمودي (+ Montant)',
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'clear_divisions',
          icon: Icons.layers_clear_rounded,
          label: 'مسح القواطع الداخلية',
          isDark: isDark,
        ),
        const PopupMenuDivider(height: 1),
        _buildContextMenuItem(
          value: 'customize_glass',
          icon: Icons.view_in_ar_rounded,
          label: 'تخصيص نوع الزجاج والبانو...',
          isDark: isDark,
        ),
        if (selectedZone.content == ZoneContent.singleSash) ...[
          _buildContextMenuItem(
            value: 'sash_dir_right',
            icon: Icons.arrow_forward_rounded,
            label: 'فتح إلى اليمين (Droite)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'sash_dir_left',
            icon: Icons.arrow_back_rounded,
            label: 'فتح إلى اليسار (Gauche)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'sash_dir_top',
            icon: Icons.arrow_upward_rounded,
            label: 'سوفلي / فتح لأعلى (Vasistas/Haut)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'sash_dir_bottom',
            icon: Icons.arrow_downward_rounded,
            label: 'فتح لأسفل (Bas)',
            isDark: isDark,
          ),
        ],
      ],
      if (isFrame)
        _buildContextMenuItem(
          value: 'frame_delete',
          icon: Icons.delete_outline_rounded,
          label: 'حذف هذا الإطار',
          color: Colors.redAccent,
          isDark: isDark,
        ),
      if (_isShutterSelected)
        _buildContextMenuItem(
          value: 'shutter_open_options',
          icon: Icons.tune_rounded,
          label: 'إعدادات الستار والمحرك...',
          isDark: isDark,
        ),
      const PopupMenuDivider(height: 1),
      _buildContextMenuItem(
        value: 'undo',
        icon: Icons.undo_rounded,
        label: 'تراجع (Undo)',
        enabled: widget.model.canUndo,
        isDark: isDark,
      ),
      _buildContextMenuItem(
        value: 'redo',
        icon: Icons.redo_rounded,
        label: 'إعادة (Redo)',
        enabled: widget.model.canRedo,
        isDark: isDark,
      ),
    ];

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    String? selectedValue;
    _isContextMenuOpen = true;
    try {
      selectedValue = await showMenu<String>(
      context: context,
        position: RelativeRect.fromRect(
          Rect.fromLTWH(globalPosition.dx, globalPosition.dy, 1, 1),
          Offset.zero & overlay.size,
      ),
        constraints: const BoxConstraints(maxWidth: 420, maxHeight: 560),
      color: isDark ? const Color(0xFF252536) : Colors.white,
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isDark ? Colors.white24 : Colors.grey.shade300,
          width: 0.8,
        ),
      ),
        items: menuItems,
      );
    } finally {
      _isContextMenuOpen = false;
    }

    /* Previous pointer-anchored popup intentionally replaced by the centered
       dialog above so editing actions remain readable on phones and desktops.
        PopupMenuItem<String>(
          enabled: false,
          height: 32,
          child: Row(
            children: [
              Icon(
                _isShutterSelected
                    ? Icons.menu_rounded
                    : (isFrame
                          ? Icons.crop_square_rounded
                          : Icons.window_rounded),
                size: 16,
                color: isDark ? Colors.blue.shade300 : Colors.blue.shade700,
              ),
              const SizedBox(width: 8),
              Text(
                _isShutterSelected
                    ? 'خصائص الستار'
                    : (isFrame ? 'خصائص الإطار' : 'خصائص المنطقة والضلفة'),
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white70 : Colors.black87,
                ),
              ),
            ],
          ),
        ),
        const PopupMenuDivider(height: 1),

        if (selectedZone != null && !_isShutterSelected && !isFrame) ...[
          _buildContextMenuItem(
            value: 'content_fixe',
            icon: Icons.crop_landscape_rounded,
            label: 'زجاج ثابت (Fixe)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_single_sash',
            icon: Icons.sensor_door_outlined,
            label: 'ضلفة عادية (Ouvrant Simple)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_double_sash',
            icon: Icons.door_sliding_outlined,
            label: 'ضلفة فرنسية مزدوجة (Double Ouvrant)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_2',
            icon: Icons.compare_arrows_rounded,
            label: 'منزلق 2 ضلف (Coulissant 2 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_3',
            icon: Icons.view_column_rounded,
            label: 'منزلق 3 ضلف (Coulissant 3 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_sliding_4',
            icon: Icons.grid_view_rounded,
            label: 'منزلق 4 ضلف (Coulissant 4 Vantaux)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'content_vide',
            icon: Icons.check_box_outline_blank_rounded,
            label: 'تفريغ (Vide)',
            isDark: isDark,
          ),
          const PopupMenuDivider(height: 1),

          _buildContextMenuItem(
            value: 'add_h_division',
            icon: Icons.border_horizontal_rounded,
            label: 'إضافة قاطع أفقي (+ Traverse)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'add_v_division',
            icon: Icons.border_vertical_rounded,
            label: 'إضافة قاطع عمودي (+ Montant)',
            isDark: isDark,
          ),
          _buildContextMenuItem(
            value: 'clear_divisions',
            icon: Icons.layers_clear_rounded,
            label: 'مسح القواطع الداخلية',
            isDark: isDark,
          ),
          const PopupMenuDivider(height: 1),

          _buildContextMenuItem(
            value: 'customize_glass',
            icon: Icons.view_in_ar_rounded,
            label: 'تخصيص نوع الزجاج والبانو...',
            isDark: isDark,
          ),

          if (selectedZone.content == ZoneContent.singleSash) ...[
            _buildContextMenuItem(
              value: 'sash_dir_right',
              icon: Icons.arrow_forward_rounded,
              label: 'فتح إلى اليمين (Droite)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_left',
              icon: Icons.arrow_back_rounded,
              label: 'فتح إلى اليسار (Gauche)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_top',
              icon: Icons.arrow_upward_rounded,
              label: 'سوفلي / فتح لأعلى (Vasistas/Haut)',
              isDark: isDark,
            ),
            _buildContextMenuItem(
              value: 'sash_dir_bottom',
              icon: Icons.arrow_downward_rounded,
              label: 'فتح لأسفل (Bas)',
              isDark: isDark,
            ),
          ],
        ],

        if (isFrame) ...[
          _buildContextMenuItem(
            value: 'frame_delete',
            icon: Icons.delete_outline_rounded,
            label: 'حذف هذا الإطار',
            color: Colors.redAccent,
            isDark: isDark,
          ),
        ],

        if (_isShutterSelected) ...[
          _buildContextMenuItem(
            value: 'shutter_open_options',
            icon: Icons.tune_rounded,
            label: 'إعدادات الستار والمحرك...',
            isDark: isDark,
          ),
        ],

        const PopupMenuDivider(height: 1),

        _buildContextMenuItem(
          value: 'undo',
          icon: Icons.undo_rounded,
          label: 'تراجع (Undo)',
          enabled: widget.model.canUndo,
          isDark: isDark,
        ),
        _buildContextMenuItem(
          value: 'redo',
          icon: Icons.redo_rounded,
          label: 'إعادة (Redo)',
          enabled: widget.model.canRedo,
          isDark: isDark,
        ),
      ],
    ); */

    if (selectedValue == null) return;

    switch (selectedValue) {
      case 'content_fixe':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.fixedGlass);
        break;
      case 'content_single_sash':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.singleSash);
        break;
      case 'content_double_sash':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.doubleSash);
        break;
      case 'content_sliding_2':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 2,
          );
        break;
      case 'content_sliding_3':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 3,
          );
        break;
      case 'content_sliding_4':
        if (selectedZone != null)
          _paintZoneContentFromUi(
            selectedZone,
            ZoneContent.slidingSash,
            slidingSashesCount: 4,
          );
        break;
      case 'content_vide':
        if (selectedZone != null)
          _paintZoneContentFromUi(selectedZone, ZoneContent.empty);
        break;
      case 'add_h_division':
        if (selectedZone != null) {
          selectedZone.innerH += 1;
          selectedZone.innerHPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'add_v_division':
        if (selectedZone != null) {
          selectedZone.innerV += 1;
          selectedZone.innerVPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'clear_divisions':
        if (selectedZone != null) {
          selectedZone.innerH = 0;
          selectedZone.innerV = 0;
          selectedZone.rightInnerH = 0;
          selectedZone.rightInnerV = 0;
          selectedZone.innerHPositions = const [];
          selectedZone.innerVPositions = const [];
          selectedZone.rightInnerHPositions = const [];
          selectedZone.rightInnerVPositions = const [];
          widget.model.refreshUI();
        }
        break;
      case 'customize_glass':
        _setViewState(() {
          _isBottomPanelExpanded = true;
          _activeBottomTab = 2;
        });
        break;
      case 'sash_dir_right':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.right);
        break;
      case 'sash_dir_left':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.left);
        break;
      case 'sash_dir_top':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.top);
        break;
      case 'sash_dir_bottom':
        widget.model.setSelectedZoneOpenDirection(OpenDirection.bottom);
        break;
      case 'frame_delete':
        widget.model.deleteSelectedFrame();
        break;
      case 'shutter_open_options':
        _setViewState(() {
          _isShutterSelected = true;
          _isBottomPanelExpanded = true;
          _activeShutterTab = 0;
        });
        break;
      case 'undo':
        widget.model.undo();
        if (_isShutterSelected &&
            !widget.model.isShutterOnly &&
            (widget.model.zones.isNotEmpty || !widget.model.hasShutter)) {
          _setViewState(() {
            _isShutterSelected = false;
          });
        }
        break;
      case 'redo':
        widget.model.redo();
        if (widget.model.isShutterOnly && !_isShutterSelected) {
          _setViewState(() {
            _isShutterSelected = true;
          });
        }
        break;
    }
  }

  PopupMenuItem<String> _buildContextMenuItem({
    required String value,
    required IconData icon,
    required String label,
    required bool isDark,
    bool enabled = true,
    Color? color,
  }) {
    final itemColor =
        color ??
        (enabled ? (isDark ? Colors.white : Colors.black87) : Colors.grey);
    return PopupMenuItem<String>(
      value: value,
      enabled: enabled,
      height: 36,
      child: Row(
        children: [
          SizedBox(
            width: 28,
            child: Icon(icon, size: 18, color: itemColor),
          ),
          Expanded(
            child: Text(
              Localization.translate(
                label,
                Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                ).language,
              ),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: itemColor,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: 28),
        ],
      ),
    );
  }

  void _showResizeDialog(BuildContext context, {required bool focusWidth}) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final widthCtrl = TextEditingController(
      text: widget.model.width > 0 ? widget.model.width.toInt().toString() : '',
    );
    final heightCtrl = TextEditingController(
      text: widget.model.height > 0
          ? widget.model.height.toInt().toString()
          : '',
    );
    final heightFocus = FocusNode();
    BuildContext? dialogContext;
    void apply() {
      final w = double.tryParse(widthCtrl.text);
      final h = double.tryParse(heightCtrl.text);
      // The layout decides the minimum (frame bars, mullions and the sash
      // bars of every zone); one bar length is the maximum.
      final wLimits = widget.model.outerDimensionLimits(
        isWidth: true,
        otherSide: h,
      );
      final hLimits = widget.model.outerDimensionLimits(
        isWidth: false,
        otherSide: w,
      );
      if (!_acceptDimension(w, wLimits.min, wLimits.max) ||
          !_acceptDimension(h, hLimits.min, hLimits.max)) {
        return;
      }
      widget.model.resizeWindow(w!, h!);
      // `context` here belongs to the drawing route. Popping it returns the
      // user to the system selector instead of dismissing this dialog.
      final activeDialogContext = dialogContext;
      if (activeDialogContext != null) {
        Navigator.of(activeDialogContext, rootNavigator: true).pop();
      }
    }

    showDialog(
      context: context,
      builder: (context) {
        dialogContext = context;
        final isDark = Theme.of(context).brightness == Brightness.dark;
        return AlertDialog(
          backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
          title: Text(
            Localization.translate('تعديل قياسات النافذة', lang),
            style: TextStyle(
              color: isDark ? Colors.white : Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthCtrl,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onChanged: (value) {
                    if (value.length == 4) {
                      heightFocus.requestFocus();
                      heightCtrl.selection = TextSelection(
                        baseOffset: 0,
                        extentOffset: heightCtrl.text.length,
                      );
                    }
                  },
                  onSubmitted: (_) => apply(),
                  autofocus: focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'العرض الإجمالي (mm)',
                      lang,
                    ),
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white70 : Colors.blueGrey,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: heightCtrl,
                  focusNode: heightFocus,
                  inputFormatters: [
                    FilteringTextInputFormatter.digitsOnly,
                    LengthLimitingTextInputFormatter(4),
                  ],
                  onSubmitted: (_) => apply(),
                  autofocus: !focusWidth,
                  keyboardType: TextInputType.number,
                  style: TextStyle(
                    color: isDark ? Colors.white : Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'الارتفاع الإجمالي (mm)',
                      lang,
                    ),
                    labelStyle: TextStyle(
                      color: isDark ? Colors.white70 : Colors.black87,
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: isDark ? Colors.white70 : Colors.blueGrey,
                      ),
                    ),
                    focusedBorder: const OutlineInputBorder(
                      borderSide: BorderSide(color: Colors.blue, width: 2),
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue,
                foregroundColor: Colors.white,
              ),
              onPressed: apply,
              child: Text(
                Localization.translate('تطبيق', lang),
                style: const TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  void _showPresetSystemsDialog(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final presets =
        <
          ({
            WindowPresetType type,
            String title,
            String subtitle,
            double defaultW,
            double defaultH,
            IconData icon,
            Color accentColor,
          })
        >[
          (
            type: WindowPresetType.windowNoShutter,
            title: 'نافذة بدون ستار',
            subtitle: 'دلفة أو دلفتين تفتح جانبياً حسب العرض',
            defaultW: 1200.0,
            defaultH: 1200.0,
            icon: Icons.window_rounded,
            accentColor: Colors.blue,
          ),
          (
            type: WindowPresetType.windowWithShutter,
            title: 'نافذة مع ستار',
            subtitle: 'دلفة أو دلفتين مع صندوق الستار (Monobloc)',
            defaultW: 1200.0,
            defaultH: 1400.0,
            icon: Icons.layers_rounded,
            accentColor: Colors.teal,
          ),
          (
            type: WindowPresetType.slidingNoShutter,
            title: 'نافذة جرارة بدون ستار',
            subtitle: 'نافذة منزلقة بضلفتين (2 Vantaux)',
            defaultW: 1400.0,
            defaultH: 1200.0,
            icon: Icons.sync_alt_rounded,
            accentColor: Colors.indigo,
          ),
          (
            type: WindowPresetType.slidingWithShutter,
            title: 'نافذة جرارة مع الستار',
            subtitle: 'نافذة منزلقة بضلفتين مع صندوق الستار',
            defaultW: 1400.0,
            defaultH: 1400.0,
            icon: Icons.dock_rounded,
            accentColor: Colors.cyan,
          ),
          (
            type: WindowPresetType.singleDoor,
            title: 'باب بضلفة واحدة مع قفل',
            subtitle: 'بروفيل ضلفة 105، قفل بمفتاح وبدون إطار سفلي',
            defaultW: 900.0,
            defaultH: 2100.0,
            icon: Icons.door_back_door_rounded,
            accentColor: Colors.deepOrange,
          ),
          (
            type: WindowPresetType.doubleDoor,
            title: 'باب بضلفتين مع قفل',
            subtitle: 'ضلفتين 105، قفل بمفتاح وبدون إطار سفلي',
            defaultW: 1600.0,
            defaultH: 2100.0,
            icon: Icons.meeting_room_rounded,
            accentColor: Colors.purple,
          ),
          (
            type: WindowPresetType.shutterOnly,
            title: 'ستار وحده',
            subtitle: 'صندوق وشفرات الستار مع المجاري فقط',
            defaultW: 1200.0,
            defaultH: 1200.0,
            icon: Icons.table_rows_rounded,
            accentColor: Colors.orange,
          ),
          (
            type: WindowPresetType.topOpeningSmallWindow,
            title: 'نافذة صغيرة تفتح من الأعلى',
            subtitle: 'مفصلات سفلية وتفتح من الأعلى (Soufflet)',
            defaultW: 600.0,
            defaultH: 500.0,
            icon: Icons.vertical_align_top_rounded,
            accentColor: Colors.green,
          ),
        ];

    WindowPresetType selectedType = WindowPresetType.windowNoShutter;
    final initialW = widget.model.width > 200 ? widget.model.width : 1200.0;
    final initialH = widget.model.height > 200 ? widget.model.height : 1200.0;
    final widthCtrl = TextEditingController(text: initialW.toInt().toString());
    final heightCtrl = TextEditingController(text: initialH.toInt().toString());

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            void apply(WindowPresetType type) async {
              final w = double.tryParse(widthCtrl.text);
              final h = double.tryParse(heightCtrl.text);
              if (w == null || h == null || w < 200 || h < 200) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      Localization.translate(
                        'يرجى إدخال أبعاد صحيحة (العرض والارتفاع أكبر من 200 مم)',
                        lang,
                      ),
                    ),
                    backgroundColor: Colors.red.shade700,
                  ),
                );
                return;
              }
              Navigator.of(dialogContext).pop();
              await widget.model.applyPresetTemplate(
                preset: type,
                newWidth: w,
                newHeight: h,
              );
              if (mounted) _setViewState(() {});
            }

            final currentPreset = presets.firstWhere(
              (p) => p.type == selectedType,
            );

            return AlertDialog(
              backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              contentPadding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.blue.shade700.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(
                      Icons.auto_awesome_mosaic_rounded,
                      color: Colors.blue.shade700,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate('الأنظمة الجاهزة', lang),
                          style: TextStyle(
                            color: isDark ? Colors.white : Colors.black87,
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          Localization.translate(
                            'أدخل أبعاد الإطار واختر النموذج المطلوب ليرسم تلقائياً بدقة',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 11,
                            color: isDark ? Colors.white60 : Colors.black54,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 720,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.white.withValues(alpha: 0.05)
                              : Colors.blue.shade50.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.white12
                                : Colors.blue.shade100,
                          ),
                        ),
                        child: Row(
                          children: [
                            _PresetThumbnailWidget(
                              preset: selectedType,
                              width: 80,
                              height: 80,
                              isDark: isDark,
                              accentColor: currentPreset.accentColor,
                            ),
                            const SizedBox(width: 14),
                            Expanded(
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: widthCtrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(5),
                                      ],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'العرض الإجمالي (mm)',
                                          lang,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.straighten_rounded,
                                          size: 20,
                                        ),
                                        isDense: true,
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF262638)
                                            : Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: TextField(
                                      controller: heightCtrl,
                                      keyboardType: TextInputType.number,
                                      inputFormatters: [
                                        FilteringTextInputFormatter.digitsOnly,
                                        LengthLimitingTextInputFormatter(5),
                                      ],
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: 16,
                                      ),
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'الارتفاع الإجمالي (mm)',
                                          lang,
                                        ),
                                        prefixIcon: const Icon(
                                          Icons.height_rounded,
                                          size: 20,
                                        ),
                                        isDense: true,
                                        filled: true,
                                        fillColor: isDark
                                            ? const Color(0xFF262638)
                                            : Colors.white,
                                        border: OutlineInputBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                      const SizedBox(height: 14),
                      Wrap(
                        spacing: 10,
                        runSpacing: 10,
                        children: presets.map((preset) {
                          final isSelected = selectedType == preset.type;
                          return InkWell(
                            borderRadius: BorderRadius.circular(12),
                            onTap: () {
                              setDialogState(() {
                                selectedType = preset.type;
                                widthCtrl.text = preset.defaultW
                                    .toInt()
                                    .toString();
                                heightCtrl.text = preset.defaultH
                                    .toInt()
                                    .toString();
                              });
                            },
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 180),
                              width: 340,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? preset.accentColor.withValues(
                                        alpha: isDark ? 0.25 : 0.12,
                                      )
                                    : (isDark
                                          ? const Color(0xFF252538)
                                          : Colors.grey.shade50),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: isSelected
                                      ? preset.accentColor
                                      : (isDark
                                            ? Colors.white12
                                            : Colors.grey.shade300),
                                  width: isSelected ? 2 : 1,
                                ),
                              ),
                              child: Row(
                                children: [
                                  _PresetThumbnailWidget(
                                    preset: preset.type,
                                    width: 52,
                                    height: 52,
                                    isDark: isDark,
                                    accentColor: preset.accentColor,
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          Localization.translate(
                                            preset.title,
                                            lang,
                                          ),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                            color: isSelected
                                                ? preset.accentColor
                                                : (isDark
                                                      ? Colors.white
                                                      : Colors.black87),
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          Localization.translate(
                                            preset.subtitle,
                                            lang,
                                          ),
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            color: isDark
                                                ? Colors.white60
                                                : Colors.black54,
                                          ),
                                          maxLines: 2,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          '${Localization.translate('القياس الافتراضي', lang)}: ${preset.defaultW.toInt()} × ${preset.defaultH.toInt()}',
                                          style: TextStyle(
                                            fontSize: 9.5,
                                            color: preset.accentColor
                                                .withValues(alpha: 0.9),
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(
                                      Icons.arrow_forward_rounded,
                                      size: 20,
                                    ),
                                    color: preset.accentColor,
                                    tooltip: Localization.translate(
                                      'رسم هذا النظام',
                                      lang,
                                    ),
                                    onPressed: () => apply(preset.type),
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: const TextStyle(color: Colors.grey),
                  ),
                ),
                ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: currentPreset.accentColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: () => apply(selectedType),
                  icon: const Icon(Icons.brush_rounded, size: 18),
                  label: Text(
                    Localization.translate('تطبيق ورسم النظام', lang),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showMullionFrameSelectorDialog(
    BuildContext context,
    MullionProfileType type,
  ) async {
    final frames = _availableMullionFrameSections();
    // Nothing to choose between: apply the only frame straight away.
    if (frames.length == 1) {
      await _applyMullionFrameSection(type, frames.single);
      return;
    }
    final title = type == MullionProfileType.flat
        ? 'Cadre doublé - اختر إطار التقسيم'
        : 'Cadre مفرد / 140 - اختر إطار التقسيم';

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(title),
        children: [
          if (frames.isEmpty)
            Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                _tr('لا توجد إطارات متوفرة لهذه السلسلة'),
                textDirection: TextDirection.rtl,
              ),
            )
          else
            ...frames.map((frame) {
              final code = (frame['code'] ?? '').toString();
              final name = (frame['name'] ?? 'بدون اسم').toString();
              final label = code.isEmpty ? name : '$code - $name';
              final selected = _selectedMullionFrameMatches(frame, type);
              return SimpleDialogOption(
                onPressed: () async {
                  Navigator.pop(dialogContext);
                  await _applyMullionFrameSection(type, frame);
                },
                child: Row(
                  children: [
                    SectionImageWidget(
                      code: code,
                      name: name,
                      imagePath: frame['image_path']?.toString(),
                      size: 28,
                      fallbackIcon: type == MullionProfileType.flat
                          ? Icons.splitscreen_rounded
                          : Icons.view_headline_rounded,
                      fallbackColor: selected
                          ? Colors.blue.shade700
                          : Colors.grey.shade500,
                    ),
                    const SizedBox(width: 12),
                    Expanded(child: Text(label)),
                    if (selected)
                      Icon(Icons.check_circle, color: Colors.green.shade700),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _showMullionTypeDialog(BuildContext context) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final selection = widget.model.selection;
    if (selection.type != SelectionType.mullion ||
        selection.isHorizontalMullion == null ||
        selection.mullionPosition == null) {
      return;
    }

    final key =
        '${selection.isHorizontalMullion! ? 'H' : 'V'}_${selection.mullionPosition!.toStringAsFixed(1)}';
    final currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;

    SimpleDialogOption typeOption(
      BuildContext dialogContext,
      MullionProfileType type,
      String label,
      IconData icon,
    ) {
      return SimpleDialogOption(
        onPressed: () {
          Navigator.pop(dialogContext);
          if (type == MullionProfileType.standard) {
            _setViewState(() {
              widget.model.setMullionProfile(type);
            });
          } else {
            unawaited(_showMullionFrameSelectorDialog(context, type));
          }
        },
        child: Row(
          children: [
            Icon(
              icon,
              color: type == currentType
                  ? Colors.green.shade700
                  : Colors.blueGrey,
            ),
            const SizedBox(width: 12),
            Expanded(child: Text(label)),
            if (type != MullionProfileType.standard)
              const Icon(Icons.chevron_right_rounded, color: Colors.blueGrey),
            if (type == currentType)
              Icon(Icons.check_circle, color: Colors.green.shade700),
          ],
        ),
      );
    }

    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text(Localization.translate('نوع التقسيم', lang)),
        children: [
          typeOption(
            dialogContext,
            MullionProfileType.standard,
            Localization.translate('Traverse — تقسيم عادي', lang),
            Icons.horizontal_rule_rounded,
          ),
          typeOption(
            dialogContext,
            MullionProfileType.flat,
            Localization.translate('Cadre double — إطار مزدوج', lang),
            Icons.splitscreen_rounded,
          ),
          typeOption(
            dialogContext,
            MullionProfileType.grooved,
            Localization.translate('Cadre 140 — إطار بتجويف واحد', lang),
            Icons.view_headline_rounded,
          ),
          if (currentType == MullionProfileType.grooved)
            SimpleDialogOption(
              onPressed: () {
                widget.model.toggleGroovedMullionCavity(
                  selection.isHorizontalMullion!,
                  selection.mullionPosition!,
                );
                Navigator.pop(dialogContext);
              },
              child: Row(
                children: [
                  const Icon(Icons.swap_horiz_rounded, color: Colors.blue),
                  const SizedBox(width: 12),
                  Text(Localization.translate('عكس اتجاه التجويف', lang)),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMullionToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String key =
        "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(1)}";
    MullionProfileType currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    Widget toolbarButton({
      required String label,
      required IconData icon,
      required bool selected,
      required VoidCallback onPressed,
      bool showSubmenuIndicator = false,
    }) {
      return Padding(
        padding: const EdgeInsets.only(left: 8),
        child: OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.white,
            side: BorderSide(
              color: selected ? Colors.white : Colors.white38,
              width: selected ? 1.6 : 1.0,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          ),
          icon: Icon(icon, size: 16),
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: const TextStyle(fontSize: 12)),
              if (showSubmenuIndicator) ...[
                const SizedBox(width: 3),
                const Icon(Icons.chevron_right_rounded, size: 15),
              ],
            ],
          ),
          onPressed: onPressed,
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.blue.shade900.withValues(alpha: 0.85),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.drag_indicator_rounded,
              color: Colors.white,
              size: 18,
            ),
            const SizedBox(width: 6),
            Text(
              Localization.translate('العمود محدد', lang),
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            const SizedBox(width: 12),
            toolbarButton(
              label: 'Traverse',
              icon: Icons.horizontal_rule_rounded,
              selected: currentType == MullionProfileType.standard,
              onPressed: () =>
                  widget.model.setMullionProfile(MullionProfileType.standard),
            ),
            toolbarButton(
              label: 'Cadre doublé',
              icon: Icons.splitscreen_rounded,
              selected: currentType == MullionProfileType.flat,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.flat,
              ),
            ),
            toolbarButton(
              label: 'Cadre 140',
              icon: Icons.view_headline_rounded,
              selected: currentType == MullionProfileType.grooved,
              showSubmenuIndicator: true,
              onPressed: () => _showMullionFrameSelectorDialog(
                context,
                MullionProfileType.grooved,
              ),
            ),
            if (currentType == MullionProfileType.grooved)
              toolbarButton(
                label: Localization.translate('قلب الجهة', lang),
                icon: Icons.swap_horiz_rounded,
                selected: widget.model.isGroovedMullionCavityOnPositiveSide(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
                onPressed: () => widget.model.toggleGroovedMullionCavity(
                  widget.model.selection.isHorizontalMullion!,
                  widget.model.selection.mullionPosition!,
                ),
              ),
            const SizedBox(width: 12),
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.white,
                size: 16,
              ),
              label: Text(
                Localization.translate('حذف', lang),
                style: const TextStyle(color: Colors.white, fontSize: 12),
              ),
              onPressed: () => widget.model.deleteSelectedMullion(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInnerDivisionToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.shade900.withValues(alpha: 0.8),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            Localization.translate('التقسيم محدد (اسحب للتحريك)', lang),
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(color: Colors.white),
            ),
            onPressed: () => widget.model.deleteSelectedInnerDivision(),
          ),
        ],
      ),
    );
  }

  Widget _buildFrameToolbar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.indigo.shade900.withValues(alpha: 0.85),
      child: Row(
        children: [
          const Icon(Icons.crop_square_rounded, color: Colors.white),
          const SizedBox(width: 10),
          Text(
            Localization.translate('الإطار محدد', lang),
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          const Spacer(),
          if (widget.model.getFrameRects().length > 1)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red.shade600,
              ),
              icon: const Icon(
                Icons.delete_sweep,
                color: Colors.white,
                size: 18,
              ),
              label: Text(
                Localization.translate('حذف الإطار', lang),
                style: const TextStyle(color: Colors.white),
              ),
              onPressed: () => widget.model.deleteSelectedFrame(),
            ),
        ],
      ),
    );
  }

  Future<void> _showSideCoverSegmentDialog(
    BuildContext context,
    String side,
  ) async {
    // Long-press callbacks can finish after WindowView has been removed
    // (for example when the user confirms another dialog or leaves the page).
    // Keep one live page context and never use the callback's stale context
    // after an async dialog returns.
    if (!mounted || !context.mounted) return;
    final pageContext = this.context;
    final model = widget.model;
    final lang = Provider.of<AppSettingsProvider>(
      pageContext,
      listen: false,
    ).language;
    final sideLength = model.sideCoverSideLength(side);
    if (sideLength <= 0) return;

    final existing = model.sideCoverSegmentForSide(side);
    final vertical = side == 'left' || side == 'right';
    final leading = vertical ? 'الأعلى' : 'اليسار';
    final trailing = vertical ? 'الأسفل' : 'اليمين';
    final sideLabel = vertical
        ? (side == 'right' ? 'اليمنى' : 'اليسرى')
        : (side == 'top' ? 'العلوية' : 'السفلية');
    final startController = TextEditingController(
      text: (existing?.startOffset ?? 0).toStringAsFixed(0),
    );
    final secondController = TextEditingController(
      text: (existing?.length ?? sideLength).toStringAsFixed(0),
    );
    final visibleController = TextEditingController(
      text: (existing?.visibleWidth ?? model.sideCoverWidth).toStringAsFixed(0),
    );
    bool fromTrailing = false;
    bool useEndOffset = false;
    SideCoverSegment? segmentToSave;
    bool removeExistingSegment = false;

    double readValue(TextEditingController controller) =>
        double.tryParse(controller.text.trim().replaceAll(',', '.')) ?? -1;

    try {
      await showDialog<void>(
        context: pageContext,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final startLabel = fromTrailing ? trailing : leading;
            final endLabel = fromTrailing ? leading : trailing;
            return AlertDialog(
              title: Text(
                '${Localization.translate('تخصيص غطاء الجهة', lang)} ${Localization.translate(sideLabel, lang)}',
              ),
              content: SingleChildScrollView(
                child: SizedBox(
                  width: 330,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: Text(
                              '${Localization.translate('من', lang)} ${Localization.translate(leading, lang)}',
                            ),
                            selected: !fromTrailing,
                            onSelected: (_) => setDialogState(() {
                              fromTrailing = false;
                            }),
                          ),
                          ChoiceChip(
                            label: Text(
                              '${Localization.translate('من', lang)} ${Localization.translate(trailing, lang)}',
                            ),
                            selected: fromTrailing,
                            onSelected: (_) => setDialogState(() {
                              fromTrailing = true;
                            }),
                          ),
                        ],
                      ),
                      SwitchListTile(
                        contentPadding: EdgeInsets.zero,
                        dense: true,
                        title: Text(
                          Localization.translate(
                            'إدخال النهاية بدل الطول',
                            lang,
                          ),
                        ),
                        value: useEndOffset,
                        onChanged: (value) => setDialogState(() {
                          useEndOffset = value;
                        }),
                      ),
                      TextField(
                        controller: startController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText:
                              '${Localization.translate('بداية الغطاء من', lang)} ${Localization.translate(startLabel, lang)} (${Localization.translate('مم', lang)})',
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: secondController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: useEndOffset
                              ? '${Localization.translate('نهاية الغطاء قبل', lang)} ${Localization.translate(endLabel, lang)} (${Localization.translate('مم', lang)})'
                              : Localization.translate(
                                  'طول الغطاء على الإطار (مم)',
                                  lang,
                                ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      TextField(
                        controller: visibleController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'العرض الظاهر خارج الإطار (مم)',
                            lang,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        '${Localization.translate('طول الجهة:', lang)} ${sideLength.toStringAsFixed(0)} ${Localization.translate('مم', lang)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.blueGrey,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                if (existing != null)
                  TextButton.icon(
                    onPressed: () {
                      if (!dialogContext.mounted) return;
                      removeExistingSegment = true;
                      Navigator.of(dialogContext).pop();
                    },
                    icon: const Icon(Icons.delete_outline, color: Colors.red),
                    label: Text(
                      Localization.translate('حذف', lang),
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
                TextButton(
                  onPressed: () {
                    if (dialogContext.mounted) {
                      Navigator.of(dialogContext).pop();
                    }
                  },
                  child: Text(Localization.translate('إلغاء', lang)),
                ),
                ElevatedButton(
                  onPressed: () {
                    final first = readValue(startController);
                    final second = readValue(secondController);
                    final visible = readValue(visibleController);
                    if (first < 0 || second < 0 || visible < 0) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.maybeOf(pageContext)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate('أدخل قياسات صحيحة', lang),
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    double start;
                    double end;
                    if (!fromTrailing) {
                      start = first;
                      end = useEndOffset ? sideLength - second : start + second;
                    } else {
                      end = sideLength - first;
                      start = useEndOffset ? second : end - second;
                    }
                    start = start.clamp(0.0, sideLength).toDouble();
                    end = end.clamp(0.0, sideLength).toDouble();
                    if (end <= start) {
                      if (pageContext.mounted) {
                        ScaffoldMessenger.maybeOf(pageContext)?.showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'يجب أن تكون نهاية الغطاء بعد بدايته',
                                lang,
                              ),
                            ),
                          ),
                        );
                      }
                      return;
                    }

                    if (!mounted || !dialogContext.mounted) return;
                    segmentToSave = SideCoverSegment(
                      side: side,
                      startOffset: start,
                      endOffset: end,
                      visibleWidth: visible,
                    );
                    Navigator.of(dialogContext).pop();
                  },
                  child: Text(Localization.translate('حفظ', lang)),
                ),
              ],
            );
          },
        ),
      );

      // `showDialog` completes when Navigator.pop is called, while the dialog
      // widgets can remain mounted during the reverse route animation. Do not
      // notify the drawing model in that interval: rebuilding the page would
      // make inherited-context lookups run from a deactivating dialog tree.
      await Future<void>.delayed(const Duration(milliseconds: 250));
      if (!mounted) return;
      if (removeExistingSegment) {
        model.removeSideCoverSegment(side);
      } else if (segmentToSave != null) {
        model.saveSideCoverSegment(segmentToSave!);
      }
    } finally {
      startController.dispose();
      secondController.dispose();
      visibleController.dispose();
    }
  }

  Future<void> _showDrawingDefaultSeriesDialog() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String t(String value) => Localization.translate(value, lang);
    final opening = <int, AluminumSeries>{};
    final sliding = <int, AluminumSeries>{};
    for (final system in widget.model.availableSystems) {
      for (final series in _seriesForScope(system, 'opening')) {
        opening[series.id] = series;
      }
      for (final series in _seriesForScope(system, 'sliding')) {
        sliding[series.id] = series;
      }
    }
    int? openingId = prefs.getInt('default_opening_series_id');
    int? slidingId = prefs.getInt('default_sliding_series_id');
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) {
          Widget selector(
            String label,
            Map<int, AluminumSeries> items,
            int? selected,
            ValueChanged<int?> changed,
          ) {
            return DropdownButtonFormField<int>(
              value: items.containsKey(selected) ? selected : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: t(label)),
              hint: Text(t('تلقائي (افتراضي النظام)')),
              items: items.values
                  .map(
                    (series) => DropdownMenuItem<int>(
                      value: series.id,
                      child: Text(series.name, overflow: TextOverflow.ellipsis),
                    ),
                  )
                  .toList(),
              onChanged: saving ? null : changed,
            );
          }

          return AlertDialog(
            title: Text(t('السلاسل الافتراضية للورشة')),
            content: SizedBox(
              width: 420,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t('اختر السلاسل للنوافذ الجديدة. لن يتغير الرسم الحالي.'),
                    ),
                    const SizedBox(height: 16),
                    selector(
                      'سلسلة الفتح الافتراضية (Battant):',
                      opening,
                      openingId,
                      (value) => update(() => openingId = value),
                    ),
                    const SizedBox(height: 16),
                    selector(
                      'سلسلة المنزلق الافتراضية (Coulissant):',
                      sliding,
                      slidingId,
                      (value) => update(() => slidingId = value),
                    ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(dialogContext),
                child: Text(t('إلغاء')),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        update(() => saving = true);
                        if (openingId != null) {
                          await prefs.setInt(
                            'default_opening_series_id',
                            openingId!,
                          );
                        }
                        if (slidingId != null) {
                          await prefs.setInt(
                            'default_sliding_series_id',
                            slidingId!,
                          );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      },
                child: Text(t('حفظ')),
              ),
            ],
          );
        },
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final isStandaloneShutterContext =
        widget.model.isShutterOnly || widget.model.drawNextShapeAsShutterOnly;
    final isShutterContext = isStandaloneShutterContext || _isShutterSelected;
    final rawShutterColorItems =
        widget.model.availableAccessoryColors.isNotEmpty
        ? widget.model.availableAccessoryColors
        : widget.model.availableColors;
    final shutterColorItems = <Map<String, dynamic>>[];
    final seenShutterColorIds = <String>{};
    for (final c in rawShutterColorItems) {
      final idStr = (c['id'] ?? c['name'] ?? '').toString();
      if (idStr.isNotEmpty && seenShutterColorIds.add(idStr)) {
        shutterColorItems.add(c);
      }
    }
    final selectedShutterColorId = widget.model.effectiveShutterColor?['id']
        ?.toString();
    final selectedShutterColor =
        (selectedShutterColorId != null &&
            shutterColorItems.any(
              (color) => color['id']?.toString() == selectedShutterColorId,
            ))
        ? shutterColorItems.firstWhere(
            (color) => color['id']?.toString() == selectedShutterColorId,
          )
        : null;
    // The selectors describe the drawing itself, not the route that happened
    // to open it. An edited sliding-only drawing can arrive through the
    // mixed editor route, so using `widget.systemMode` here showed the false
    // hints "سلسلة الفتح / Gamme coulissant" instead of its saved BS90.
    final hasSliding = widget.model.zones.any(
      (zone) => zone.content == ZoneContent.slidingSash,
    );
    final hasOpening = widget.model.zones.any(
      (zone) =>
          zone.content == ZoneContent.singleSash ||
          zone.content == ZoneContent.doubleSash,
    );

    // قواعد الظهور والاختفاء بدقة:
    // 1) عند الدخول إلى صفحة جديدة: تظهر السلسلتان معاً
    // 2) عند رسم نافذة منزلقة فقط: تبقى المنزلقة وتختفي الفتح
    // 3) عند رسم نافذة فتح فقط: تبقى الفتح وتختفي المنزلقة
    // 4) عند رسم الاثنين معاً: يظهران معاً
    final bool showOpeningSelector;
    final bool showSlidingSelector;

    if (hasSliding && !hasOpening) {
      showOpeningSelector = false;
      showSlidingSelector = true;
    } else if (hasOpening && !hasSliding) {
      showOpeningSelector = true;
      showSlidingSelector = false;
    } else {
      showOpeningSelector = true;
      showSlidingSelector = true;
    }

    // 🔵 قائمة سلاسل الفتح فقط (تظهر باللون الأزرق - بدون خلط بالمنزلق)
    final openingItemsList = () {
      final list = <AluminumSeries>[];
      for (final system in widget.model.availableSystems) {
        for (final series in system.series) {
          if (isOpeningSeriesForDrawing(series, system) &&
              !isSlidingSeriesForDrawing(series)) {
            if (!list.any((s) => s.id == series.id)) {
              list.add(series);
            }
          }
        }
      }
      return list;
    }();

    // القيمة الفعالة لسلسلة الفتح
    final safeOpeningValue =
        (widget.model.activeSeries != null &&
            openingItemsList.any((s) => s.id == widget.model.activeSeries!.id))
        ? openingItemsList.firstWhere(
            (s) => s.id == widget.model.activeSeries!.id,
          )
        : (openingItemsList.isNotEmpty ? openingItemsList.first : null);

    if (widget.model.activeSeries == null && safeOpeningValue != null) {
      widget.model.activeSeries = safeOpeningValue;
    }

    // التوافق مع النظام: إذا تم تعيين أو اختيار سلسلة فتح، نحدد نظامها
    final activeOpeningSystem = profileSystemForSeries(
      widget.model.availableSystems,
      safeOpeningValue ?? widget.model.activeSeries,
    );

    // 🟢 قائمة سلاسل المنزلق فقط (تظهر باللون الأخضر)
    // إذا كانت المنزلقة وحدها: تحتوي جميع قوائم السلاسل المنزلقة
    // إذا كان هناك فتح: تختار من نفس النظام التابع للفتح ولا تخرج عنه
    final slidingItemsList = () {
      final list = <AluminumSeries>[];
      final bool slidingAlone = hasSliding && !hasOpening;

      if (!slidingAlone && activeOpeningSystem != null) {
        for (final s in activeOpeningSystem.series) {
          if (isSlidingSeriesForDrawing(s) &&
              !isOpeningSeriesForDrawing(s, activeOpeningSystem)) {
            if (!list.any((existing) => existing.id == s.id)) {
              list.add(s);
            }
          }
        }
      }

      if (list.isEmpty || slidingAlone) {
        for (final system in widget.model.availableSystems) {
          for (final s in system.series) {
            if (isSlidingSeriesForDrawing(s) &&
                !isOpeningSeriesForDrawing(s, system)) {
              if (!list.any((existing) => existing.id == s.id)) {
                list.add(s);
              }
            }
          }
        }
      }
      return list;
    }();

    // اختيار تلقائي لسلسلة منزلقة من نفس النظام عند وجود سلسلة فتح
    if (activeOpeningSystem != null && !hasSliding) {
      final sameSystemSliding = activeOpeningSystem.series
          .where(
            (s) =>
                isSlidingSeriesForDrawing(s) &&
                !isOpeningSeriesForDrawing(s, activeOpeningSystem),
          )
          .toList();
      if (sameSystemSliding.isNotEmpty) {
        final cur = widget.model.activeSlidingSeries;
        if (cur == null || !sameSystemSliding.any((s) => s.id == cur.id)) {
          widget.model.activeSlidingSeries = sameSystemSliding.first;
        }
      }
    }

    // القيمة الفعالة لسلسلة المنزلق
    final safeSlidingValue =
        (widget.model.activeSlidingSeries != null &&
            slidingItemsList.any(
              (s) => s.id == widget.model.activeSlidingSeries!.id,
            ))
        ? slidingItemsList.firstWhere(
            (s) => s.id == widget.model.activeSlidingSeries!.id,
          )
        : (slidingItemsList.isNotEmpty ? slidingItemsList.first : null);

    if (widget.model.activeSlidingSeries == null && safeSlidingValue != null) {
      widget.model.activeSlidingSeries = safeSlidingValue;
    }

    return AppBar(
      backgroundColor: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      foregroundColor: isDark ? Colors.white : Colors.black,
      elevation: 0.5,
      titleSpacing: 8,
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        physics: const AlwaysScrollableScrollPhysics(),
        child: Row(
          children: [
            if (isShutterContext && shutterColorItems.isNotEmpty) ...[
              Container(
                constraints: BoxConstraints(
                  maxWidth: _isWindowsDesktop ? 170 : 110,
                ),
                padding: EdgeInsets.symmetric(
                  horizontal: _isWindowsDesktop ? 8 : 4,
                  vertical: 0,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.orange.shade900.withValues(alpha: 0.3)
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark
                        ? Colors.orange.shade800
                        : Colors.orange.shade200,
                  ),
                ),
                child: DropdownButton<Map<String, dynamic>>(
                  isExpanded: true,
                  value: selectedShutterColor,
                  dropdownColor: isDark
                      ? const Color(0xFF1E1E2C)
                      : Colors.white,
                  hint: Text(
                    Localization.translate('لون الستار', lang),
                    style: TextStyle(
                      color: isDark
                          ? Colors.orange.shade300
                          : Colors.orange.shade800,
                      fontSize: _isWindowsDesktop ? 12 : 11,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  underline: const SizedBox(),
                  icon: _isWindowsDesktop
                      ? Icon(
                          Icons.keyboard_arrow_down,
                          color: isDark
                              ? Colors.orange.shade300
                              : Colors.orange.shade800,
                          size: 18,
                        )
                      : const SizedBox.shrink(),
                  iconSize: _isWindowsDesktop ? 24 : 0,
                  items: shutterColorItems.map((colorData) {
                    final colorName =
                        (colorData['name'] ?? colorData['color_name'] ?? '')
                            .toString();
                    final parsedColor = getEffectiveGradientColors(
                      FrameColor.white,
                      colorData,
                    )[1];
                    final woodImage = _getWoodTextureImage(colorData);
                    return DropdownMenuItem<Map<String, dynamic>>(
                      value: colorData,
                      child: Row(
                        children: [
                          Container(
                            width: 16,
                            height: 16,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: woodImage != null ? null : parsedColor,
                              image: woodImage,
                              border: Border.all(
                                color: isDark
                                    ? Colors.white38
                                    : Colors.grey.shade400,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              _trColor(colorName),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.orange.shade300
                                    : Colors.orange.shade800,
                                fontSize: 12,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                  onChanged: (newColor) {
                    if (newColor == null) return;
                    widget.model.selectedShutterColor =
                        Map<String, dynamic>.from(newColor);
                    unawaited(widget.model.updateShutterDefaultsIfNeeded());
                    widget.model.refreshUI();
                  },
                ),
              ),
            ],
            if (!isStandaloneShutterContext &&
                widget.model.availableSystems.isNotEmpty) ...[
              // 🔵 قائمة سلسلة الفتح (تظهر باللون الأزرق دائماً - وتختفي عند رسم منزلق فقط)
              if (showOpeningSelector && openingItemsList.isNotEmpty) ...[
                Container(
                  constraints: BoxConstraints(
                    maxWidth: _isWindowsDesktop ? 160 : 110,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: _isWindowsDesktop ? 8 : 4,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.shade900.withValues(alpha: 0.3)
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? Colors.blue.shade800
                          : Colors.blue.shade300,
                    ),
                  ),
                  child: DropdownButton<AluminumSeries>(
                    isExpanded: true,
                    value: safeOpeningValue,
                    dropdownColor: isDark
                        ? const Color(0xFF1E1E2C)
                        : Colors.white,
                    hint: Text(
                      Localization.translate('سلسلة الفتح', lang),
                      style: TextStyle(
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade800,
                        fontSize: _isWindowsDesktop ? 12 : 11,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    underline: const SizedBox(),
                    icon: _isWindowsDesktop
                        ? Icon(
                            Icons.keyboard_arrow_down,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade800,
                            size: 18,
                          )
                        : const SizedBox.shrink(),
                    iconSize: _isWindowsDesktop ? 24 : 0,
                    items: openingItemsList.map((series) {
                      return DropdownMenuItem<AluminumSeries>(
                        value: series,
                        child: Text(
                          series.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.blue.shade300
                                : Colors.blue.shade800,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                      );
                    }).toList(),
                    onChanged: (AluminumSeries? newSeries) async {
                      if (newSeries != null) {
                        await widget.model.setActiveSeries(newSeries);
                        // اختيار تلقائي لسلسلة منزلقة من نفس النظام
                        final ownerSystem = profileSystemForSeries(
                          widget.model.availableSystems,
                          newSeries,
                        );
                        if (ownerSystem != null) {
                          final compatibleSliding = ownerSystem.series
                              .where(
                                (s) =>
                                    isSlidingSeriesForDrawing(s) &&
                                    !isOpeningSeriesForDrawing(s, ownerSystem),
                              )
                              .toList();
                          if (compatibleSliding.isNotEmpty) {
                            await widget.model.setActiveSlidingSeries(
                              compatibleSliding.first,
                            );
                          }
                        }
                        if (mounted) _setViewState(() {});
                      }
                    },
                  ),
                ),
              ],

              // مسافة فاصلة إذا ظهرت القائمتان معاً
              if (showOpeningSelector &&
                  showSlidingSelector &&
                  openingItemsList.isNotEmpty &&
                  slidingItemsList.isNotEmpty)
                const SizedBox(width: 8),

              // 🟢 قائمة سلسلة المنزلق (تظهر باللون الأخضر دائماً - وتختفي عند رسم فتح فقط)
              if (showSlidingSelector && slidingItemsList.isNotEmpty) ...[
                Container(
                  constraints: BoxConstraints(
                    maxWidth: _isWindowsDesktop ? 160 : 110,
                  ),
                  padding: EdgeInsets.symmetric(
                    horizontal: _isWindowsDesktop ? 8 : 4,
                    vertical: 0,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.green.shade900.withValues(alpha: 0.3)
                        : Colors.green.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? Colors.green.shade800
                          : Colors.green.shade300,
                    ),
                  ),
                  child: DropdownButton<AluminumSeries>(
                    isExpanded: true,
                    value: safeSlidingValue,
                    hint: Text(
                      Localization.translate('سلسلة المنزلق', lang),
                      style: TextStyle(
                        color: isDark
                            ? Colors.green.shade300
                            : Colors.green.shade800,
                        fontSize: _isWindowsDesktop ? 12 : 11,
                        fontFamily: 'Cairo',
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    dropdownColor: isDark
                        ? const Color(0xFF1E1E2C)
                        : Colors.white,
                    underline: const SizedBox(),
                    icon: _isWindowsDesktop
                        ? Icon(
                            Icons.keyboard_arrow_down,
                            color: isDark
                                ? Colors.green.shade300
                                : Colors.green.shade800,
                            size: 18,
                          )
                        : const SizedBox.shrink(),
                    iconSize: _isWindowsDesktop ? 24 : 0,
                    items: slidingItemsList.map((series) {
                      return DropdownMenuItem<AluminumSeries>(
                        value: series,
                        child: Text(
                          series.name,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: isDark
                                ? Colors.green.shade300
                                : Colors.green.shade800,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.visible,
                        ),
                      );
                    }).toList(),
                    onChanged: (AluminumSeries? newSeries) async {
                      if (newSeries != null) {
                        await widget.model.setActiveSlidingSeries(newSeries);
                        if (mounted) _setViewState(() {});
                      }
                    },
                  ),
                ),
              ],
            ],

            const SizedBox(width: 8),

            // 🟢 زر التراجع
            if (_isWindowsDesktop)
              ..._buildWindowsAppBarDrawingControls(context),

            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canUndo
                  ? () {
                      widget.model.undo();
                      if (_isShutterSelected &&
                          !widget.model.isShutterOnly &&
                          (widget.model.zones.isNotEmpty ||
                              !widget.model.hasShutter)) {
                        _setViewState(() {
                          _isShutterSelected = false;
                        });
                      }
                    }
                  : null,
              icon: const Icon(Icons.undo_rounded),
              tooltip: Localization.translate('تراجع', lang),
              color: widget.model.canUndo
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.white38 : Colors.black26),
            ),

            // 🟢 زر الإعادة (Redo)
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canRedo
                  ? () {
                      widget.model.redo();
                      if (widget.model.isShutterOnly && !_isShutterSelected) {
                        _setViewState(() {
                          _isShutterSelected = true;
                        });
                      }
                    }
                  : null,
              icon: const Icon(Icons.redo_rounded),
              tooltip: Localization.translate('إعادة', lang),
              color: widget.model.canRedo
                  ? (isDark ? Colors.white : Colors.black87)
                  : (isDark ? Colors.white38 : Colors.black26),
            ),

            // When enabled, every new outer frame copies its neighbour's
            // corresponding width or height.
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: Icon(
                Icons.copy_all_rounded,
                color: widget.model.copyPreviousFrameSize
                    ? (isDark ? Colors.lightBlueAccent : Colors.blue.shade700)
                    : (isDark ? Colors.white70 : Colors.black54),
              ),
              tooltip: widget.model.copyPreviousFrameSize
                  ? Localization.translate(
                      'نسخ قياس الإطار السابق: مفعّل',
                      lang,
                    )
                  : Localization.translate('نسخ قياس الإطار السابق', lang),
              onPressed: widget.model.toggleCopyPreviousFrameSize,
            ),

            // 🟢 زر مسح الرسم بالكامل
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: const Icon(Icons.delete_sweep_rounded, color: Colors.red),
              tooltip: Localization.translate('مسح الرسم', lang),
              onPressed: () => _showClearAllDialog(context),
            ),
          ],
        ),
      ),
      actions: [
        IconButton(
          tooltip: Localization.translate('معاينة ثلاثية الأبعاد', lang),
          onPressed: _open3DPreview,
          icon: Icon(
            Icons.view_in_ar_rounded,
            color: isDark ? Colors.lightBlueAccent : Colors.blue.shade700,
          ),
        ),
        // The mobile bottom panel already owns the quantity/cost action.
        // Keeping this large AppBar action on a narrow screen squeezed the
        // drawing controls and produced horizontal overflow.
        if (_isWindowsDesktop)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 14, start: 6),
            child: Center(
              child: Tooltip(
                message: Localization.translate(
                  'فتح جدول الكمية والتكلفة',
                  lang,
                ),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: isDark
                          ? const [Color(0xFF047857), Color(0xFF065F46)]
                          : const [Color(0xFF10B981), Color(0xFF047857)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(
                        alpha: isDark ? 0.16 : 0.3,
                      ),
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF065F46).withValues(alpha: 0.28),
                        blurRadius: 10,
                        offset: const Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => _openMaterialConsumptionScreen(context),
                      child: Padding(
                        padding: const EdgeInsetsDirectional.fromSTEB(
                          11,
                          7,
                          13,
                          7,
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 25,
                              height: 25,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.18),
                                borderRadius: BorderRadius.circular(7),
                              ),
                              child: const Icon(
                                Icons.receipt_long_rounded,
                                size: 16,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              Localization.translate('الكمية والتكلفة', lang),
                              style: const TextStyle(
                                fontSize: 12,
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(width: 4),
                            const Icon(
                              Icons.arrow_forward_ios_rounded,
                              size: 11,
                              color: Colors.white70,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        if (!_isWindowsDesktop)
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: IconButton(
              icon: const Icon(Icons.receipt_long_rounded, color: Colors.green),
              tooltip: Localization.translate('الكمية والتكلفة', lang),
              onPressed: () => _openMaterialConsumptionScreen(context),
            ),
          ),
      ],
    );
  }

  Widget _buildSplitToolbar(BuildContext context, bool hasSelection) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: isDark ? const Color(0xFF1E1E2C) : Colors.white,
      width: double.infinity,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            if (widget.model.zones.isEmpty &&
                !widget.model.isShutterOnly &&
                widget.model.drawingStart == null) ...[
              InkWell(
                onTap: () => _showPresetSystemsDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: isDark
                        ? Colors.blue.shade900.withValues(alpha: 0.4)
                        : Colors.blue.shade50,
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isDark
                          ? Colors.blue.shade700
                          : Colors.blue.shade300,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.auto_awesome_mosaic_rounded,
                        size: 15,
                        color: isDark
                            ? Colors.blue.shade300
                            : Colors.blue.shade700,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        Localization.translate('الأنظمة الجاهزة', lang),
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: isDark
                              ? Colors.blue.shade200
                              : Colors.blue.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            InkWell(
              onTap: () {
                _showResizeDialog(context, focusWidth: true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: Text(
                  'Dim: ${widget.model.width.toInt()} * ${widget.model.height.toInt()}',
                  style: TextStyle(
                    fontSize: 12,
                    color: isDark ? Colors.blue.shade300 : Colors.blue.shade900,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            // زر التبديل بين الأوضاع (اللمس فقط)
            if (!_isWindowsDesktop)
            InkWell(
              onTap: () {
                if (widget.model.isDrawingMode) {
                  _stopDrawingTimer();
                } else {
                  _startDrawingTimer();
                }
                _setViewState(() {});
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.model.isDrawingMode
                      ? Colors.green.shade600
                      : Colors.blueGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  widget.model.isDrawingMode
                      ? Localization.translate('وضع الرسم', lang)
                      : Localization.translate('وضع التحريك', lang),
                  style: const TextStyle(
                    fontSize: 12,
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            InkWell(
              onTap: _activateShutterFromDesign,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.model.hasShutter
                      ? Colors.orange.shade600
                      : Colors.blueGrey,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      widget.model.hasShutter
                          ? Icons.layers_rounded
                          : Icons.add_box_rounded,
                      color: Colors.white,
                      size: 16,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      Localization.translate('ستار', lang),
                      style: const TextStyle(
                        fontSize: 12,
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            if (widget.model.hasShutter) ...[
              const SizedBox(width: 8),
              InkWell(
                onTap: () => _showSplitShutterDialog(context),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: widget.model.isShutterSplit
                        ? Colors.teal.shade600
                        : Colors.blueGrey,
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.view_column_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 5),
                      Text(
                        widget.model.isShutterSplit
                            ? '${Localization.translate('فصل الصناديق', lang)} (${widget.model.effectiveShutterSplits.length})'
                            : Localization.translate('فصل الصناديق', lang),
                        style: const TextStyle(
                          fontSize: 12,
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (widget.model.canChooseSeparateShutterBelt) ...[
                const SizedBox(width: 8),
                Tooltip(
                  message: Localization.translate(
                    'separate_shutter_belt_hint',
                    lang,
                  ),
                  child: InkWell(
                    onTap: () => _setViewState(() {
                      widget.model.setSeparateShutterBeltInside(
                        !widget.model.separateShutterBeltInside,
                      );
                    }),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: widget.model.separateShutterBeltInside
                            ? Colors.brown.shade600
                            : Colors.blueGrey,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.settings_input_component_rounded,
                            color: Colors.white,
                            size: 16,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            Localization.translate(
                              widget.model.separateShutterBeltInside
                                  ? 'separate_shutter_belt_inside'
                                  : 'separate_shutter_belt_outside',
                              lang,
                            ),
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ],
            const SizedBox(width: 8),
            // زر إعادة التكبير
            InkWell(
              onTap: () {
                _setViewState(() {
                  _userScale = 1.0;
                  _userPan = Offset.zero;
                });
              },
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: isDark
                      ? Colors.blue.shade900.withValues(alpha: 0.3)
                      : Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                    color: isDark ? Colors.blue.shade800 : Colors.blue.shade200,
                  ),
                ),
                child: Icon(
                  Icons.zoom_out_map_rounded,
                  color: isDark ? Colors.blue.shade300 : Colors.blue,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showClearAllDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text(
              _tr('مسح الرسم'),
              style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
            ),
          ],
        ),
        content: Text(
          _tr('هل أنت متأكد أنك تريد مسح الرسم بالكامل والبدء من جديد؟'),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _tr('إلغاء'),
              style: TextStyle(color: Colors.grey, fontWeight: FontWeight.bold),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              widget.model.clearAll();
              Navigator.pop(context);
            },
            child: Text(
              _tr('نعم، امسح'),
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showProfileAngleDialog(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final junctions = widget.model.getAdjacentFrameJunctions();
    final hasJunctions = junctions.isNotEmpty;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 16,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const Icon(
                                Icons.square_foot_rounded,
                                color: Colors.blue,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                Localization.translate(
                                  "بروفيل الزاوية 90° (Profil d'angle / Tube carré)",
                                  lang,
                                ),
                                style: const TextStyle(
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      // Corner Frame Compatibility Card
                      Container(
                        margin: const EdgeInsets.only(bottom: 12),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: widget.model.frameSwitchedForProfileAngle
                              ? Colors.green.withValues(alpha: 0.1)
                              : Colors.blue.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: widget.model.frameSwitchedForProfileAngle
                                ? Colors.green.shade600
                                : Colors.blue.shade400,
                            width: 1,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              widget.model.frameSwitchedForProfileAngle
                                  ? Icons.published_with_changes
                                  : Icons.info_outline,
                              color: widget.model.frameSwitchedForProfileAngle
                                  ? Colors.green.shade800
                                  : Colors.blue.shade800,
                              size: 20,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    Localization.translate(
                                      'توافق الإطارات عند الزاوية 90°',
                                      lang,
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12.5,
                                      color:
                                          widget
                                              .model
                                              .frameSwitchedForProfileAngle
                                          ? Colors.green.shade900
                                          : Colors.blue.shade900,
                                    ),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    widget.model.frameSwitchedForProfileAngle
                                        ? '${Localization.translate('تم استبدال الإطار تلقائياً بإطار بدون غطاء مدمج مطابق في العرض الظاهر ليناسب زاوية 90°:', lang)} (${widget.model.profileAngleFrameSwitchNotice ?? ""})'
                                        : Localization.translate(
                                            'لا يمكن تركيب إطار بغطاء مدمج عند الزاوية 90°؛ يقوم النظام تلقائياً باختيار إطار بدون غطاء مدمج مطابق تماماً في العرض الظاهر.',
                                            lang,
                                          ),
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (hasJunctions) ...[
                        Text(
                          Localization.translate(
                            'حدد الفواصل بين الإطارات المتلاصقة التي يركب فيها أنبوب الزاوية 90°:',
                            lang,
                          ),
                          style: const TextStyle(
                            fontSize: 13,
                            color: Colors.grey,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            ElevatedButton.icon(
                              style: ElevatedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.select_all, size: 18),
                              label: Text(
                                Localization.translate('تحديد الكل', lang),
                              ),
                              onPressed: () {
                                widget.model.setAllProfileAngleJunctions(true);
                                _warnProfileAngleFrames();
                                setModalState(() {});
                                _setViewState(() {});
                              },
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 8,
                                ),
                              ),
                              icon: const Icon(Icons.clear_all, size: 18),
                              label: Text(
                                Localization.translate('إلغاء الكل', lang),
                              ),
                              onPressed: () {
                                widget.model.setAllProfileAngleJunctions(false);
                                setModalState(() {});
                                _setViewState(() {});
                              },
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        ...junctions.map((j) {
                          final isSelected = widget
                              .model
                              .activeProfileAngleJunctions
                              .contains(j.index);
                          return Card(
                            elevation: isSelected ? 2 : 0,
                            color: isSelected
                                ? Colors.blue.withOpacity(0.08)
                                : Theme.of(context).cardColor,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                              side: BorderSide(
                                color: isSelected
                                    ? Colors.blue
                                    : Colors.grey.shade300,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            margin: const EdgeInsets.symmetric(vertical: 4),
                            child: CheckboxListTile(
                              title: Text(
                                j.localizedLabel(lang),
                                style: TextStyle(
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  color: isSelected
                                      ? Colors.blue.shade900
                                      : null,
                                ),
                              ),
                              subtitle: Text(
                                Localization.translate(
                                  'طول القطاع: ${j.height.toStringAsFixed(0)} مم',
                                  lang,
                                ),
                                style: const TextStyle(fontSize: 12),
                              ),
                              value: isSelected,
                              activeColor: Colors.blue,
                              onChanged: (checked) {
                                widget.model.toggleProfileAngleJunction(
                                  j.index,
                                  checked,
                                );
                                _warnProfileAngleFrames();
                                setModalState(() {});
                                _setViewState(() {});
                              },
                            ),
                          );
                        }),
                        const SizedBox(height: 8),
                        ListTile(
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                            side: BorderSide(
                              color:
                                  widget
                                      .model
                                      .activeProfileAngleJunctions
                                      .isEmpty
                                  ? Colors.red.shade300
                                  : Colors.grey.shade300,
                            ),
                          ),
                          tileColor:
                              widget.model.activeProfileAngleJunctions.isEmpty
                              ? Colors.red.withOpacity(0.06)
                              : null,
                          leading: const Icon(
                            Icons.block_rounded,
                            color: Colors.red,
                          ),
                          title: Text(
                            Localization.translate(
                              'إلغاء بروفيل الزاوية بين الإطارات (إيقاف)',
                              lang,
                            ),
                            style: TextStyle(
                              color: Colors.red.shade700,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          subtitle: Text(
                            Localization.translate(
                              'بدون أي أنبوب زاوية بين الإطارات المتلاصقة',
                              lang,
                            ),
                            style: const TextStyle(fontSize: 12),
                          ),
                          trailing:
                              widget.model.activeProfileAngleJunctions.isEmpty
                              ? const Icon(Icons.check, color: Colors.red)
                              : null,
                          onTap: () {
                            widget.model.setAllProfileAngleJunctions(false);
                            setModalState(() {});
                            _setViewState(() {});
                          },
                        ),
                        const SizedBox(height: 10),
                        SwitchListTile(
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 4,
                          ),
                          secondary: Icon(
                            Icons.view_in_ar_rounded,
                            color: widget.model.viewAs90DegreeCorner
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          title: Text(
                            Localization.translate(
                              'عرض الرسم بزاوية 90° (منظور ثلاثي الأبعاد)',
                              lang,
                            ),
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          subtitle: Text(
                            Localization.translate(
                              'يُظهر الإطار الثاني ملتفاً بزاوية 90° في الرسم مع مسقط أفقي معماري',
                              lang,
                            ),
                            style: const TextStyle(fontSize: 11),
                          ),
                          value: widget.model.viewAs90DegreeCorner,
                          activeColor: Colors.blue,
                          onChanged: (val) {
                            widget.model.viewAs90DegreeCorner = val;
                            setModalState(() {});
                            _setViewState(() {});
                          },
                        ),
                        const Divider(height: 24),
                      ],
                      if (!hasJunctions)
                        Text(
                          Localization.translate(
                            'بروفيل الزاوية يركب بين إطارين متلاصقين فقط، وليس على أطراف الإطار. ألصق إطاراً بإطار ثم فعّله بينهما.',
                            lang,
                          ),
                          style: TextStyle(
                            fontSize: 12.5,
                            color: Colors.orange.shade900,
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showFrameSideProfileDialog(BuildContext context) async {
    final frame = widget.model.frameRectForSelection(
      widget.model.selection.zoneId,
    );
    if (frame == null) return;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String tr(String ar, String fr, String en) => switch (lang) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      AppLanguage.arabic => ar,
    };

    final sliding = widget.model.frameUsesSlidingSeries(frame);
    final base = widget.model.frameSectionForRect(frame)?.toMap();
    if (base == null) return;

    bool isRowSliding(Map<String, dynamic> row) {
      final role = (row['role_key'] ?? row['role'] ?? row['design_role'] ?? '')
          .toString()
          .toLowerCase();
      if (role == 'sliding_frame' || role == 'frame_sliding') return true;
      final uScope =
          (row['usage_scope'] ??
                  row['design_usage_scope'] ??
                  row['sharing_usage_scope'] ??
                  '')
              .toString()
              .toLowerCase();
      if (uScope == 'sliding') return true;
      if (uScope == 'opening' || uScope == 'ouvrant') return false;
      final text =
          '${row['label'] ?? ''} ${row['name'] ?? ''} ${row['type'] ?? ''} ${row['code'] ?? ''}'
              .toLowerCase();
      return RegExp(
        r'\b\d+\s*rail|raill|monorail|couliss|glissi|galandage|سحاب|منزلق|جرار',
      ).hasMatch(text);
    }

    final raw = sliding
        ? _slidingFrameProfiles.where((r) => isRowSliding(r)).toList()
        : (_openingFrameProfiles.isNotEmpty
                  ? _openingFrameProfiles
                  : _frameProfiles)
              .where((r) => !isRowSliding(r))
              .toList();

    final allRows = <Map<String, dynamic>>[...raw];
    if (widget.model.hasFrameJoinRules) {
      final baseSec = AluminumSection.fromMap(base);
      for (final system in widget.model.availableSystems) {
        for (final series in system.series) {
          if (series.id == baseSec.seriesId) continue;
          for (final section in series.sections) {
            final type = section.type.toLowerCase();
            if (!(section.isFrame ||
                type == 'frame' ||
                type.contains('cadre') ||
                type.contains('dormant'))) {
              continue;
            }
            final map = section.toMap();
            if (isRowSliding(map) != sliding) continue;
            if (!widget.model.framesCanJoin(baseSec, section)) continue;
            allRows.add({
              ...map,
              'source_series_id': series.id,
              'series_id': series.id,
            });
          }
        }
      }
    }

    final baseSection = AluminumSection.fromMap(base);
    final candidates = <Map<String, dynamic>>[];
    final seen = <String>{};
    for (final item in allRows) {
      final id = (item['id'] ?? '').toString();
      if (id.isEmpty || !seen.add(id)) continue;
      final same = id == (base['id'] ?? '').toString();
      if (same) {
        candidates.add(item);
        continue;
      }

      // Check sliding vs opening compatibility
      if (isRowSliding(item) != sliding) continue;

      // Only the frames set for this frame in the frame pairing page.
      if (widget.model.frameFitsSideOf(
        baseSection,
        AluminumSection.fromMap(item),
      )) {
        candidates.add(item);
      }
    }
    if (!seen.contains((base['id'] ?? '').toString())) {
      candidates.insert(0, base);
    }

    final selectedSides = <String>{};
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          Widget sideButton(String side, IconData icon, String label) {
            final selected = selectedSides.contains(side);
            final override = widget.model.frameSideOverrideForRect(frame, side);
            final automatic = widget.model.frameSideIsAutomatic(frame, side);
            return FilterChip(
              selected: selected,
              avatar: Icon(icon, size: 18),
              label: Text(
                override == null
                    ? label
                    : '$label • ${(override['code'] ?? override['name'] ?? '').toString()}'
                          '${automatic ? ' (${tr('تلقائي: بروفيل الزاوية', 'Auto : profil d\'angle', 'Auto: corner profile')})' : ''}',
              ),
              onSelected: (value) => setDialogState(() {
                value ? selectedSides.add(side) : selectedSides.remove(side);
              }),
            );
          }

          return AlertDialog(
            title: Text(
              tr(
                'تخصيص قطع الإطار حسب الجهة',
                'Personnaliser les côtés du dormant',
                'Customize frame sides',
              ),
            ),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr(
                        'حدد جهة أو عدة جهات، ثم اختر الإطار الذي ستُقطع منه. تظهر فقط إطارات السلسلة نفسها بالعرض الظاهر نفسه، أو الإطارات المرتبطة يدويًا. الجهة الملاصقة لبروفيل الزاوية تتغير تلقائيًا.',
                        'Sélectionnez un ou plusieurs côtés, puis le dormant utilisé. Seuls les dormants de la même gamme et de même largeur visible, ou liés manuellement, sont affichés. Le côté contre un profil d\'angle change automatiquement.',
                        'Select one or more sides, then choose the frame profile. Only frames of the same series with the same visible width, or linked by hand, are shown. The side against a corner profile changes automatically.',
                      ),
                    ),
                    const SizedBox(height: 12),
                    Wrap(
                      spacing: 8,
                      runSpacing: 8,
                      children: [
                        sideButton(
                          'top',
                          Icons.arrow_upward,
                          tr('علوي', 'Haut', 'Top'),
                        ),
                        sideButton(
                          'right',
                          Icons.arrow_forward,
                          tr('يمين', 'Droite', 'Right'),
                        ),
                        sideButton(
                          'bottom',
                          Icons.arrow_downward,
                          tr('سفلي', 'Bas', 'Bottom'),
                        ),
                        sideButton(
                          'left',
                          Icons.arrow_back,
                          tr('يسار', 'Gauche', 'Left'),
                        ),
                      ],
                    ),
                    const Divider(height: 28),
                    ...candidates.map((item) {
                      final code = (item['code'] ?? '').toString();
                      final name = (item['name'] ?? '').toString();
                      return ListTile(
                        minVerticalPadding: 8,
                        leading: Container(
                          width: 62,
                          height: 62,
                          padding: const EdgeInsets.all(4),
                          decoration: BoxDecoration(
                            color:
                                Theme.of(context).brightness == Brightness.dark
                                ? Colors.white10
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? Colors.white24
                                  : Colors.grey.shade300,
                            ),
                          ),
                          child: SectionImageWidget(
                            code: code,
                            name: name,
                            imagePath: item['image_path']?.toString(),
                            size: 54,
                            fallbackIcon: Icons.crop_square_rounded,
                          ),
                        ),
                        title: Text(
                          [code, name].where((e) => e.isNotEmpty).join(' - '),
                        ),
                        subtitle: Text(
                          '${tr('العرض الظاهر', 'Largeur visible', 'Visible width')}: '
                          '${widget.model.frameSectionFaceWidth(AluminumSection.fromMap(item)).toStringAsFixed(0)} mm • '
                          '${((item['couvre_joint_width'] as num?)?.toDouble() ??
                                      0) >
                                  0
                              ? tr(
                                  'بغطاء جانبي مدمج',
                                  'Avec couvre-joint intégré',
                                  'Integrated side cover',
                                )
                              : tr(
                                  'بدون غطاء جانبي مدمج',
                                  'Sans couvre-joint intégré',
                                  'Without integrated side cover',
                                )}',
                        ),
                        enabled: selectedSides.isNotEmpty,
                        onTap: selectedSides.isEmpty
                            ? null
                            : () {
                                widget.model.setFrameSideOverrides(
                                  frame,
                                  selectedSides,
                                  item,
                                );
                                Navigator.pop(dialogContext);
                              },
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: selectedSides.isEmpty
                    ? null
                    : () {
                        widget.model.setFrameSideOverrides(
                          frame,
                          selectedSides,
                          null,
                        );
                        Navigator.pop(dialogContext);
                      },
                child: Text(
                  tr(
                    'استعادة الإطار الأصلي',
                    'Rétablir le dormant',
                    'Restore original frame',
                  ),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(tr('إغلاق', 'Fermer', 'Close')),
              ),
            ],
          );
        },
      ),
    );
    if (mounted) _setViewState(() {});
  }

  void _showSplitDialog(BuildContext context, bool isHorizontal) {
    final zone = widget.model.selectedZone;
    if (zone == null) return;
    final isSashTarget =
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.doubleSash;
    final selectedRight =
        zone.content == ZoneContent.doubleSash &&
        widget.model.activeSubZone?.startsWith('right') == true;
    Rect measurementRect = zone.boundary;
    if (zone.content == ZoneContent.doubleSash) {
      final splitX =
          zone.boundary.left + zone.boundary.width * zone.doubleSashRatio;
      measurementRect = selectedRight
          ? Rect.fromLTRB(
              splitX + 2,
              zone.boundary.top,
              zone.boundary.right,
              zone.boundary.bottom,
            )
          : Rect.fromLTRB(
              zone.boundary.left,
              zone.boundary.top,
              splitX - 2,
              zone.boundary.bottom,
            );
    }
    if (isSashTarget) {
      measurementRect = widget.model.getSafeGlassRect(
        measurementRect,
        zone.sashThickness ?? widget.model.profileThickness,
      );
    }
    final double totalNetSize = isHorizontal
        ? measurementRect.height
        : measurementRect.width;
    final sashCount = widget.model.zones.fold<int>(0, (sum, candidate) {
      return sum +
          (candidate.content == ZoneContent.doubleSash
              ? 2
              : candidate.content == ZoneContent.singleSash
              ? 1
              : 0);
    });
    int parts = 2;
    bool isEqualSplit = true;
    bool fromStart = true;
    bool applyToAllSashes = false;
    TextEditingController part1Ctrl = TextEditingController();
    TextEditingController part2Ctrl = TextEditingController();
    String? splitError;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final subtextColor = isDark ? Colors.white70 : Colors.black87;
    final bgColor = isDark ? const Color(0xFF1E1E2C) : Colors.white;
    final dropdownBgColor = isDark ? const Color(0xFF2D2D3F) : Colors.white;

    String getRemainingText() {
      if (parts == 2) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        return '${Localization.translate('المتبقي', lang)}: ${(totalNetSize - p1).toStringAsFixed(1)} mm';
      } else if (parts == 3) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        double p2 = double.tryParse(part2Ctrl.text) ?? 0;
        return '${Localization.translate('القطعة الوسطى', lang)}: ${(totalNetSize - p1 - p2).toStringAsFixed(1)} mm';
      }
      return '';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: bgColor,
              title: Text(
                Localization.translate(
                  isHorizontal
                      ? 'تفاصيل التقسيم الأفقي'
                      : 'تفاصيل التقسيم العمودي',
                  lang,
                ),
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: textColor,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      title: Text(
                        Localization.translate('تقسيم متساوي', lang),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: true,
                      groupValue: isEqualSplit,
                      onChanged: (v) => setState(() => isEqualSplit = v!),
                      activeColor: Colors.blue,
                    ),
                    RadioListTile<bool>(
                      title: Text(
                        Localization.translate('قياس مخصص', lang),
                        style: TextStyle(
                          color: textColor,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: false,
                      groupValue: isEqualSplit,
                      onChanged: (v) => setState(() {
                        isEqualSplit = v!;
                        part1Ctrl.clear();
                        part2Ctrl.clear();
                      }),
                      activeColor: Colors.blue,
                    ),
                    Divider(
                      color: isDark ? Colors.white24 : Colors.grey.shade300,
                    ),
                    if (isSashTarget && sashCount > 1) ...[
                      RadioListTile<bool>(
                        title: Text(
                          Localization.translate(
                            'تطبيق على الضلفة المحددة فقط',
                            lang,
                          ),
                          style: TextStyle(color: textColor),
                        ),
                        value: false,
                        groupValue: applyToAllSashes,
                        onChanged: (value) =>
                            setState(() => applyToAllSashes = value ?? false),
                        activeColor: Colors.blue,
                      ),
                      RadioListTile<bool>(
                        title: Text(
                          Localization.translate(
                            'تطبيق نفس التقسيم على كل الضلفات',
                            lang,
                          ),
                          style: TextStyle(color: textColor),
                        ),
                        value: true,
                        groupValue: applyToAllSashes,
                        onChanged: (value) =>
                            setState(() => applyToAllSashes = value ?? true),
                        activeColor: Colors.blue,
                      ),
                      Divider(
                        color: isDark ? Colors.white24 : Colors.grey.shade300,
                      ),
                    ],
                    if (isEqualSplit)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Flexible(
                            child: Text(
                              Localization.translate(
                                'إلى كم قطعة تقسمها؟',
                                lang,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: textColor,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          const SizedBox(width: 8),
                          DropdownButton<int>(
                            value: parts,
                            dropdownColor: dropdownBgColor,
                            style: TextStyle(
                              color: textColor,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            items: List.generate(9, (index) => index + 2)
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text(
                                      '$e ${Localization.translate('قطع', lang)}',
                                    ),
                                  ),
                                )
                                .toList(),
                            onChanged: (v) => setState(() => parts = v!),
                          ),
                        ],
                      )
                    else
                      Column(
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Flexible(
                                child: Text(
                                  Localization.translate('عدد القطع:', lang),
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: textColor,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              DropdownButton<int>(
                                value: parts,
                                dropdownColor: dropdownBgColor,
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: [2, 3]
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text(
                                          '$e ${Localization.translate('قطع', lang)}',
                                        ),
                                      ),
                                    )
                                    .toList(),
                                onChanged: (v) => setState(() {
                                  parts = v!;
                                  part1Ctrl.clear();
                                  part2Ctrl.clear();
                                }),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${Localization.translate('إجمالي القياس الصافي', lang)}: ${totalNetSize.toStringAsFixed(1)} mm',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),
                          if (parts == 2) ...[
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    Localization.translate(
                                      'من أين يبدأ القياس؟',
                                      lang,
                                    ),
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: textColor,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                DropdownButton<bool>(
                                  value: fromStart,
                                  dropdownColor: dropdownBgColor,
                                  style: TextStyle(
                                    color: textColor,
                                    fontSize: 16,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text(
                                        isHorizontal
                                            ? Localization.translate(
                                                'من الأعلى',
                                                lang,
                                              )
                                            : Localization.translate(
                                                'من اليسار',
                                                lang,
                                              ),
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text(
                                        isHorizontal
                                            ? Localization.translate(
                                                'من الأسفل',
                                                lang,
                                              )
                                            : Localization.translate(
                                                'من اليمين',
                                                lang,
                                              ),
                                      ),
                                    ),
                                  ],
                                  onChanged: (v) =>
                                      setState(() => fromStart = v!),
                                ),
                              ],
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: part1Ctrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  'أدخل البُعد (mm)',
                                  lang,
                                ),
                                labelStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey,
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              getRemainingText(),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ] else if (parts == 3) ...[
                            TextField(
                              controller: part1Ctrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  isHorizontal
                                      ? 'القطعة العلوية (mm)'
                                      : 'القطعة اليسرى (mm)',
                                  lang,
                                ),
                                labelStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey,
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: part2Ctrl,
                              onChanged: (_) => setState(() {}),
                              style: TextStyle(
                                color: textColor,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: Localization.translate(
                                  isHorizontal
                                      ? 'القطعة السفلية (mm)'
                                      : 'القطعة اليمنى (mm)',
                                  lang,
                                ),
                                labelStyle: TextStyle(
                                  color: isDark
                                      ? Colors.white70
                                      : Colors.black54,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: isDark
                                        ? Colors.white24
                                        : Colors.grey,
                                  ),
                                ),
                                focusedBorder: const OutlineInputBorder(
                                  borderSide: BorderSide(color: Colors.blue),
                                ),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              getRemainingText(),
                              style: const TextStyle(
                                color: Colors.blue,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                    if (splitError != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        Localization.translate(splitError!, lang).replaceAll(
                          '{min}',
                          WindowModel.minimumZoneMm.round().toString(),
                        ),
                        style: const TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () {
                    if (zone.content != ZoneContent.empty &&
                        zone.content != ZoneContent.fixedGlass) {
                      widget.model.removeSashDivisions();
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    (zone.content != ZoneContent.empty &&
                            zone.content != ZoneContent.fixedGlass)
                        ? Localization.translate('حذف التقسيم', lang)
                        : Localization.translate('إلغاء', lang),
                    style: TextStyle(
                      color:
                          (zone.content != ZoneContent.empty &&
                              zone.content != ZoneContent.fixedGlass)
                          ? Colors.red
                          : (isDark ? Colors.white60 : Colors.grey),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    List<double>? customSizes;
                    if (!isEqualSplit) {
                      if (parts == 2) {
                        customSizes = [
                          double.tryParse(part1Ctrl.text) ?? (totalNetSize / 2),
                        ];
                      } else if (parts == 3) {
                        customSizes = [
                          double.tryParse(part1Ctrl.text) ?? (totalNetSize / 3),
                          double.tryParse(part2Ctrl.text) ?? (totalNetSize / 3),
                        ];
                      }
                    }
                    if (isSashTarget) {
                      widget.model.configureSelectedSashDivisions(
                        horizontal: isHorizontal,
                        parts: parts,
                        customSizes: customSizes,
                        fromStart: fromStart,
                        applyToAllSashes: applyToAllSashes,
                      );
                      Navigator.pop(context);
                      return;
                    }
                    String? error;
                    if (isEqualSplit) {
                      if (isHorizontal) {
                        error =widget.model.splitSelectedZoneHorizontal(parts: parts);
                      } else {
                        error = widget.model.splitSelectedZoneVertical(parts: parts);
                      }
                    } else {
                      List<double> customSizes = [];
                      if (parts == 2) {
                        double val =
                            double.tryParse(part1Ctrl.text) ??
                            (totalNetSize / 2);
                        customSizes.add(val);
                        if (isHorizontal) {
                          error = widget.model.splitSelectedZoneHorizontal(
                            parts: 2,
                            customSizes: customSizes,
                            fromTop: fromStart,
                          );
                        } else {
                          error = widget.model.splitSelectedZoneVertical(
                            parts: 2,
                            customSizes: customSizes,
                            fromLeft: fromStart,
                          );
                        }
                      } else if (parts == 3) {
                        double val1 =
                            double.tryParse(part1Ctrl.text) ??
                            (totalNetSize / 3);
                        double val2 =
                            double.tryParse(part2Ctrl.text) ??
                            (totalNetSize / 3);
                        customSizes.addAll([val1, val2]);
                        if (isHorizontal) {
                          error = widget.model.splitSelectedZoneHorizontal(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        } else {
                          error = widget.model.splitSelectedZoneVertical(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        }
                      }
                    }
                    if (error != null) {
                      setState(() => splitError = error);
                      return;
                    }
                    Navigator.pop(context);
                  },
                  child: Text(
                    Localization.translate('تطبيق', lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _buildContentToolbar(BuildContext context) {
    final zone = widget.model.selectedZone!;
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    String seriesName = activeSeriesForSystem != null
        ? activeSeriesForSystem!.name.toLowerCase()
        : '';
    final effSliding =
        widget.model.effectiveSlidingSeries ?? widget.model.activeSlidingSeries;
    String slidingSeriesName = effSliding != null
        ? effSliding.name.toLowerCase()
        : seriesName;
    final useSlidingFrame =
        widget.model.usesSlidingPrimaryProfiles ||
        zone.content == ZoneContent.slidingSash ||
        widget.systemMode == 'sliding';
    final selectedFrame = useSlidingFrame
        ? widget.model.getSlidingBaseFrameSection()?.toMap()
        : widget.model.frameOverride;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.40,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
        boxShadow: const [
          BoxShadow(color: Colors.black26, blurRadius: 4, offset: Offset(0, 2)),
        ],
      ),
      child: SingleChildScrollView(
        controller: _glassScrollController,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // 🟢 زر إعدادات الإطار المربوط بقاعدة البيانات
            Text(
              Localization.translate('إعدادات الإطار والظلفة:', lang),
              style: const TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _ContentButton(
                    label: selectedFrame != null
                        ? '${selectedFrame['name']}'
                        : Localization.translate('اختر الإطار (Cadre)', lang),
                    icon: Icons.border_outer_rounded,
                    selected: selectedFrame != null,
                    onPressed: () async {
                      final useSlidingProfiles = useSlidingFrame;
                      final selected = await showDialog<Map<String, dynamic>>(
                        context: context,
                        builder: (context) => ProfileSelectorDialog(
                          profileType: 'Frame',
                          seriesId: useSlidingProfiles
                              ? (widget.model.effectiveSlidingSeries?.id ??
                                    widget.model.activeSlidingSeries?.id)
                              : widget.model.activeSeries?.id,
                          materialType: useSlidingProfiles
                              ? (widget.model.isSlidingPVC
                                    ? 'PVC'
                                    : 'Aluminium')
                              : (widget.model.isPVC ? 'PVC' : 'Aluminium'),
                          hasShutter: widget.model.hasShutter,
                          isCaissonTunnel: widget.model.isCaissonTunnel,
                          hasSideCovers: widget.model.hasSideCovers,
                          multiFrameDrawing:
                              widget.model.getFrameRects().length > 1,
                          accessoryDrawingMode: useSlidingProfiles
                              ? AccessoryDrawingMode.sliding
                              : AccessoryDrawingMode.opening,
                          hasSimpleGlassForReducer:
                              widget.model.hasSimpleGlassForReducer,
                          hasDoubleGlassForRules:
                              widget.model.hasDoubleGlassForRules,
                        ),
                      );
                      if (selected != null) {
                        final mutableSelected = Map<String, dynamic>.from(
                          selected,
                        );
                        mutableSelected['calculated_price'] =
                            await _sectionPriceForSelectedColor(
                              mutableSelected,
                            );

                        _setViewState(() {
                          widget.model.applyFrameOverride(
                            mutableSelected,
                            sliding: useSlidingProfiles,
                            manualSelection: true,
                          );
                          widget.model.refreshUI();
                        });
                      }
                    },
                  ),

                  if (zone.content == ZoneContent.singleSash ||
                      zone.content == ZoneContent.doubleSash ||
                      zone.content == ZoneContent.slidingSash) ...[
                    const SizedBox(width: 8),
                    Builder(
                      builder: (context) {
                        final isSliding =
                            zone.content == ZoneContent.slidingSash ||
                            widget.systemMode == 'sliding';
                        final activeSashOverride = isSliding
                            ? (zone.slidingSashOverride ??
                                  widget.model.slidingSashOverride)
                            : (zone.sashOverride ?? widget.model.sashOverride);
                        return _ContentButton(
                          label: activeSashOverride != null
                              ? '${activeSashOverride['name']}'
                              : Localization.translate(
                                  'اختر الظلفة (Sash)',
                                  lang,
                                ),
                          icon: Icons.format_paint_rounded,
                          selected: activeSashOverride != null,
                          onPressed: () async {
                            final useSlidingProfiles = isSliding;
                            final selected =
                                await showDialog<Map<String, dynamic>>(
                                  context: context,
                                  builder: (context) => ProfileSelectorDialog(
                                    profileType: 'sash',
                                    seriesId: useSlidingProfiles
                                        ? (widget
                                                  .model
                                                  .effectiveSlidingSeries
                                                  ?.id ??
                                              widget
                                                  .model
                                                  .activeSlidingSeries
                                                  ?.id)
                                        : widget.model.activeSeries?.id,
                                    materialType: useSlidingProfiles
                                        ? (widget.model.isSlidingPVC
                                              ? 'PVC'
                                              : 'Aluminium')
                                        : (widget.model.isPVC
                                              ? 'PVC'
                                              : 'Aluminium'),
                                    accessoryDrawingMode: useSlidingProfiles
                                        ? AccessoryDrawingMode.sliding
                                        : AccessoryDrawingMode.opening,
                                    hasSimpleGlassForReducer:
                                        widget.model.hasSimpleGlassForReducer,
                                    hasDoubleGlassForRules:
                                        widget.model.hasDoubleGlassForRules,
                                  ),
                                );
                            if (selected != null) {
                              final mutableSelected = Map<String, dynamic>.from(
                                selected,
                              );
                              mutableSelected['calculated_price'] =
                                  await _sectionPriceForSelectedColor(
                                    mutableSelected,
                                  );

                              _setViewState(() {
                                widget.model.applySashOverride(
                                  mutableSelected,
                                  sliding: useSlidingProfiles,
                                  manualSelection: true,
                                  targetZone: zone,
                                );
                                widget.model.refreshUI();
                              });
                            }
                          },
                        );
                      },
                    ),
                    if (zone.content == ZoneContent.singleSash ||
                        zone.content == ZoneContent.doubleSash) ...[
                      Builder(
                        builder: (context) {
                          bool isCur105 = zone.isSash105;
                          if (zone.sashOverride != null) {
                            final code =
                                zone.sashOverride!['code']
                                    ?.toString()
                                    .toLowerCase() ??
                                '';
                            final name =
                                zone.sashOverride!['name']
                                    ?.toString()
                                    .toLowerCase() ??
                                '';
                            if (code.contains('104') || name.contains('104')) {
                              isCur105 = false;
                            } else if (code.contains('105') ||
                                code.contains('porte') ||
                                code.contains('ouvr') ||
                                name.contains('105') ||
                                name.contains('porte') ||
                                name.contains('ouvr') ||
                                name.contains('بورت')) {
                              isCur105 = true;
                            }
                          }
                          bool has104105Option = false;
                          if (widget.model.activeSeries != null) {
                            for (var sec
                                in widget.model.activeSeries!.sections) {
                              if (sec.type.toLowerCase() == 'sash' &&
                                  (sec.code.contains('105') ||
                                      sec.code.contains('porte') ||
                                      sec.name.contains('105') ||
                                      sec.name.contains('porte'))) {
                                has104105Option = true;
                                break;
                              }
                            }
                          }
                          if (!has104105Option) return const SizedBox.shrink();
                          return Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const SizedBox(width: 8),
                              _ContentButton(
                                label: isCur105
                                    ? Localization.translate(
                                        'الظلفة 105 (صندوق باب)',
                                        lang,
                                      )
                                    : Localization.translate(
                                        'الظلفة 104 (نافذة)',
                                        lang,
                                      ),
                                icon: Icons.door_front_door_outlined,
                                selected: isCur105,
                                onPressed: () async {
                                  await widget.model.toggleSashType104105(
                                    targetZone: zone,
                                  );
                                  _setViewState(() {});
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ],
                    if (zone.content == ZoneContent.slidingSash) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: zone.useClassicHandle
                            ? Localization.translate('مقبض كلاسيكي (فتح)', lang)
                            : Localization.translate('مقبض منزلق (جرار)', lang),
                        icon: Icons.sync_alt_rounded,
                        selected: zone.useClassicHandle,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.toggleSelectedZoneClassicHandle();
                          });
                        },
                      ),
                      if (isSlidingFaceToFaceLayout(
                        trackCount: zone.slidingTrackCount,
                        sashCount: zone.slidingSashesCount,
                      )) ...[
                        if (widget.model.supportsSlidingFaceToFace) ...[
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: Localization.translate(
                              'التقاء الظرفتين الوسطيتين (Batmo central)',
                              lang,
                            ),
                            icon: Icons.layers_rounded,
                            selected: zone.slidingFaceToFace,
                            onPressed: () {
                              _setViewState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingFaceToFace();
                              });
                            },
                          ),
                        ],
                        ...[
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: 'مقبض وسط الضلفتين',
                            icon: Icons.more_horiz_rounded,
                            selected: zone.slidingCentralHandle,
                            enabled: zone.slidingFaceToFace,
                            onPressed: () {
                              _setViewState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingCentralHandle();
                              });
                            },
                          ),
                          const SizedBox(width: 8),
                          _ContentButton(
                            label: 'مقبض الوسط الثاني (شكلي)',
                            icon: Icons.more_horiz_outlined,
                            selected: zone.slidingSecondCentralHandle,
                            enabled:
                                zone.slidingFaceToFace &&
                                zone.slidingCentralHandle,
                            onPressed: () {
                              if (!zone.slidingCentralHandle) return;
                              _setViewState(() {
                                widget.model
                                    .toggleSelectedZoneSlidingSecondCentralHandle();
                              });
                            },
                          ),
                        ],
                      ],
                    ],
                    const SizedBox(width: 8),
                    ...(zone.content == ZoneContent.doubleSash ||
                                zone.content == ZoneContent.slidingSash
                            ? [OpenDirection.left, OpenDirection.right]
                            : OpenDirection.values)
                        .map(
                          (dir) => Padding(
                            padding: const EdgeInsets.only(right: 8),
                            child: _ContentButton(
                              label: _getDirectionName(dir),
                              icon: Icons.open_with_rounded,
                              selected: zone.openDirection == dir,
                              onPressed: () => widget.model
                                  .setSelectedZoneOpenDirection(dir),
                            ),
                          ),
                        ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _tr('نوع المنطقة:'),
              style: TextStyle(
                color: Colors.black87,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  if (widget.systemMode != 'sliding') ...[
                    _ContentButton(
                      label: 'فارغة',
                      icon: Icons.crop_free_rounded,
                      selected: zone.content == ZoneContent.empty,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(ZoneContent.empty);
                      },
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'زجاج ثابت',
                      icon: Icons.window_rounded,
                      selected: zone.content == ZoneContent.fixedGlass,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(
                          ZoneContent.fixedGlass,
                        );
                      },
                    ),
                    const SizedBox(width: 8),
                    if (widget.model.canZoneHaveSash(zone)) ...[
                      _ContentButton(
                        label: 'ضلفة واحدة',
                        icon: Icons.door_back_door_rounded,
                        selected: zone.content == ZoneContent.singleSash,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.singleSash,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'ضلفتان',
                        icon: Icons.garage_rounded,
                        selected: zone.content == ZoneContent.doubleSash,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.doubleSash,
                          );
                        },
                      ),
                      const SizedBox(width: 8),
                    ],
                    if (widget.systemMode == 'mixed' && isSlidingSupported) ...[
                      const SizedBox(width: 8),
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
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                      if (slidingSeriesName.contains('h36') ||
                          slidingSeriesName.contains('67000') ||
                          slidingSeriesName.contains('67000ld') ||
                          slidingSeriesName.contains('70kp') ||
                          slidingSeriesName.contains('hps') ||
                          slidingSeriesName.contains('tpr')) ...[
                        const SizedBox(width: 8),
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
                                    _tr(
                                      'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                      ],
                      if (slidingSeriesName.contains('h36') ||
                          slidingSeriesName.contains('hps')) ...[
                        const SizedBox(width: 8),
                        _ContentButton(
                          label: _slidingCountLabel(4, lang),
                          icon: Icons.sync_alt_rounded,
                          selected:
                              zone.content == ZoneContent.slidingSash &&
                              zone.slidingSashesCount == 4,
                          onPressed: () async {
                            if (widget.model.hasArchOrSlant) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    _tr(
                                      'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                      ],
                    ],
                  ],
                  if (widget.systemMode == 'sliding' && isSlidingSupported) ...[
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
                                _tr(
                                  'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                    if (slidingSeriesName.contains('h36') ||
                        slidingSeriesName.contains('67000') ||
                        slidingSeriesName.contains('67000ld') ||
                        slidingSeriesName.contains('70kp') ||
                        slidingSeriesName.contains('hps') ||
                        slidingSeriesName.contains('tpr')) ...[
                      const SizedBox(width: 8),
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
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                    ],
                    if (slidingSeriesName.contains('h36') ||
                        slidingSeriesName.contains('hps')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: _slidingCountLabel(4, lang),
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 4,
                        onPressed: () async {
                          if (widget.model.hasArchOrSlant) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  _tr(
                                    'نظام المنزلق لا يدعم الشكل المائل والمقوس',
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
                    ],
                  ],
                ],
              ),
            ),
            if (zone.content == ZoneContent.slidingSash) ...[
              const SizedBox(height: 12),
              Text(
                _trackTitle(context.read<AppSettingsProvider>().language),
                style: const TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [2, 3, 4, 5]
                      .map(
                        (count) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ContentButton(
                            label: _trackCountLabel(
                              count,
                              context.read<AppSettingsProvider>().language,
                            ),
                            icon: Icons.view_week_rounded,
                            selected: zone.slidingTrackCount == count,
                            onPressed: () => widget.model
                                .setSelectedZoneSlidingTracks(count),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _frameTrackCompositionLabel(
                  zone.slidingTrackCount,
                  widget.model.selectedSlidingFrameIsComplete,
                  context.read<AppSettingsProvider>().language,
                ),
                style: TextStyle(color: Colors.grey.shade700, fontSize: 11),
              ),
            ],
            if (widget.model.activeSubZone != null &&
                (widget.model.activeSubZone!.contains('cell_') ||
                    zone.content == ZoneContent.fixedGlass)) ...[
              const SizedBox(height: 12),
              Text(
                _tr('مظهر القسم المحدد:'),
                style: TextStyle(
                  color: Colors.black87,
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    if (widget.model.activeSubZone != null &&
                        widget.model.activeSubZone!.contains('cell_') &&
                        (zone.content == ZoneContent.singleSash ||
                            zone.content == ZoneContent.doubleSash)) ...[
                      _ContentButton(
                        label:
                            zone.cellIsSash[widget.model.activeSubZone!] == true
                            ? 'دلفة داخلية (نشطة)'
                            : 'إضافة دلفة داخلية',
                        icon: Icons.window,
                        selected:
                            zone.cellIsSash[widget.model.activeSubZone!] ==
                            true,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.toggleSelectedCellSash();
                          });
                        },
                      ),
                      const SizedBox(width: 8),
                      _ContentButton(
                        label:
                            zone.cellIsDoubleSash[widget
                                    .model
                                    .activeSubZone!] ==
                                true
                            ? 'ضلفتان داخليتان (نشطة)'
                            : 'إضافة ضلفتان داخليتان',
                        icon: Icons.window,
                        selected:
                            zone.cellIsDoubleSash[widget
                                .model
                                .activeSubZone!] ==
                            true,
                        onPressed: () {
                          _setViewState(() {
                            widget.model.toggleSelectedCellDoubleSash();
                          });
                        },
                      ),
                      if (zone.cellIsSash[widget.model.activeSubZone!] ==
                              true ||
                          zone.cellIsDoubleSash[widget.model.activeSubZone!] ==
                              true) ...[
                        const SizedBox(width: 8),
                        Builder(
                          builder: (context) {
                            final cellKey = widget.model.activeSubZone!;
                            bool isCellSash105 = false;
                            final currentOverride =
                                zone.cellSashOverrides[cellKey];
                            if (currentOverride != null) {
                              final code =
                                  currentOverride['code']
                                      ?.toString()
                                      .toLowerCase() ??
                                  '';
                              final name =
                                  currentOverride['name']
                                      ?.toString()
                                      .toLowerCase() ??
                                  '';
                              if (code.contains('104') ||
                                  name.contains('104')) {
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

                            if (!has104105Option) {
                              return const SizedBox.shrink();
                            }

                            return _ContentButton(
                              label: isCellSash105
                                  ? 'الظلفة 105 (صندوق باب)'
                                  : 'الظلفة 104 (نافذة)',
                              icon: Icons.swap_horiz,
                              selected: true,
                              onPressed: () async {
                                await widget.model.toggleCellSashType104105(
                                  cellKey,
                                );
                                _setViewState(() {});
                              },
                            );
                          },
                        ),
                        Builder(
                          builder: (context) {
                            final cellKey = widget.model.activeSubZone!;
                            final isDouble =
                                zone.cellIsDoubleSash[cellKey] == true;
                            final currentDir = () {
                              final currentOverride =
                                  zone.cellSashOverrides[cellKey];
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
                                        ? [
                                            OpenDirection.left,
                                            OpenDirection.right,
                                          ]
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
                                              widget.model
                                                  .setCellSashOpenDirection(
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
                      ],
                    ],
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
