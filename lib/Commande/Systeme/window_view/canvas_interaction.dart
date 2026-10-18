part of '../show_system_francais.dart';

/// Pointer, drag, zoom and hit-testing on the drawing canvas.
extension _WindowViewCanvas on _WindowViewState {
  String? _getTappedCellId(WindowZone tappedZ, Offset modelPos) {
    bool isDouble = tappedZ.content == ZoneContent.doubleSash;
    bool isSingle = tappedZ.content == ZoneContent.singleSash;
    bool isSliding = tappedZ.content == ZoneContent.slidingSash;
    if (isDouble || isSingle || isSliding) {
      double splitX =
          tappedZ.boundary.left +
          tappedZ.boundary.width * tappedZ.doubleSashRatio;
      bool isRight = isDouble && (modelPos.dx > splitX);
      Rect sashR = tappedZ.boundary;
      if (isDouble) {
        final sep = 4.0;
        sashR = isRight
            ? Rect.fromLTRB(
                splitX + sep / 2,
                tappedZ.boundary.top,
                tappedZ.boundary.right,
                tappedZ.boundary.bottom,
              )
            : Rect.fromLTRB(
                tappedZ.boundary.left,
                tappedZ.boundary.top,
                splitX - sep / 2,
                tappedZ.boundary.bottom,
              );
      }
      final sashT =
          tappedZ.sashThickness ??
          widget.model.getSectionThickness('sash', fallback: 45.0);
      final glassR = sashR.deflate(sashT);
      if (glassR.contains(modelPos)) {
        int currentInnerH = isRight ? tappedZ.rightInnerH : tappedZ.innerH;
        int currentInnerV = isRight ? tappedZ.rightInnerV : tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        String sidePrefix = isDouble ? (isRight ? 'right' : 'left') : 'main';
        return '${sidePrefix}_cell_${row}_$col';
      }
    } else {
      // Non-sash zone (fixed glass, etc.)
      final glassR = tappedZ.boundary;
      if (glassR.contains(modelPos)) {
        int currentInnerH = tappedZ.innerH;
        int currentInnerV = tappedZ.innerV;
        double cellW = glassR.width / (currentInnerV + 1);
        double cellH = glassR.height / (currentInnerH + 1);
        int col = ((modelPos.dx - glassR.left) / cellW)
            .clamp(0, currentInnerV)
            .toInt();
        int row = ((modelPos.dy - glassR.top) / cellH)
            .clamp(0, currentInnerH)
            .toInt();
        return 'main_cell_${row}_$col';
      }
    }
    return null;
  }

  String _currentSelectionKey() {
    final selection = widget.model.selection;
    return '${selection.type}|${selection.zoneId}|${selection.mullionPosition}|'
        '${selection.innerDivisionIndex}|${widget.model.activeSubZone ?? ''}';
  }

  void _handleHandleDrag(Offset delta, WindowZone zone) {
    if (zone.openDirection == null && zone.content != ZoneContent.slidingSash) {
      return;
    }
    double dy = delta.dy / (_userScale * widget.model.canvasScale);
    double newRatio = zone.handlePositionRatio ?? 0.5;
    newRatio -= (dy / zone.boundary.height);
    widget.model.updateHandlePosition(zone.id, newRatio.clamp(0.1, 0.9));
  }

  // --- Hinge editing -------------------------------------------------------

  /// Delete removes the selected hinge, Escape releases it. Only active
  /// while a hinge is selected and no text field has the focus.
  bool _hingeKeyHandler(KeyEvent event) {
    if (!mounted ||
        event is! KeyDownEvent ||
        widget.model.selectedHinge == null ||
        ModalRoute.of(context)?.isCurrent != true) {
      return false;
    }
    final focus = FocusManager.instance.primaryFocus?.context;
    if (focus != null &&
        (focus.widget is EditableText ||
            focus.findAncestorWidgetOfExactType<EditableText>() != null)) {
      return false;
    }
    final key = event.logicalKey;
    if (key == LogicalKeyboardKey.delete ||
        key == LogicalKeyboardKey.backspace) {
      _removeSelectedHinge();
      return true;
    }
    if (key == LogicalKeyboardKey.escape) {
      widget.model.selectHinge(null);
      return true;
    }
    return false;
  }

  // Hit tests use the hinges exactly as the editor painted them
  // (model.hingeEdges), so selection always matches the drawing.

  double get _hingeHitRadiusPx {
    final scale = widget.model.canvasScale * _userScale;
    // Half a hinge (80 mm) on screen, never smaller than a fingertip/cursor.
    return math.max(_isWindowsDesktop ? 14.0 : 24.0, 40.0 * scale);
  }

  ({SashHingeEdge edge, int index})? _hingeAt(Offset local) {
    ({SashHingeEdge edge, int index})? best;
    var bestDistance = _hingeHitRadiusPx;
    for (final edge in widget.model.hingeEdges) {
      for (var i = 0; i < edge.centers.length; i++) {
        final d = (_modelToScreen(edge.centers[i]) - local).distance;
        if (d < bestDistance) {
          bestDistance = d;
          best = (edge: edge, index: i);
        }
      }
    }
    return best;
  }

  /// The hinged edge under [local], with the position (mm) on it.
  ({SashHingeEdge edge, double position})? _hingeEdgeAt(Offset local) {
    final modelPos = _getModelPos(local);
    for (final edge in widget.model.hingeEdges) {
      final p = edge.positionAt(modelPos);
      if (p < 0 || p > edge.length) continue;
      final onEdge = _modelToScreen(edge.pointAt(p));
      if ((onEdge - local).distance < _hingeHitRadiusPx * 0.8) {
        return (edge: edge, position: p);
      }
    }
    return null;
  }

  void _selectHinge(({SashHingeEdge edge, int index}) hit) {
    _setViewState(() {
      _isShutterSelected = false;
    });
    widget.model.selectHinge(
      SelectedHinge(hit.edge.zoneId, hit.edge.leaf, hit.index),
    );
    if (!hit.edge.editable) {
      _showHingeMessage(WindowModel.hingeObLockedKey);
    }
  }

  /// A press on a hinge drags it: directly with the mouse or in drawing
  /// mode, otherwise once it is selected (so panning over it stays panning).
  bool _startHingeDrag(ScaleStartDetails details) {
    if (details.pointerCount >= 2) return false;
    final hit = _hingeAt(details.localFocalPoint);
    if (hit == null || !hit.edge.editable) return false;
    final selected = widget.model.selectedHinge;
    final isSelected =
        selected != null &&
        selected.matches(hit.edge) &&
        selected.index == hit.index;
    if (!isSelected &&
        !widget.model.isDrawingMode &&
        details.kind != PointerDeviceKind.mouse) {
      return false;
    }
    widget.model.selectHinge(
      SelectedHinge(hit.edge.zoneId, hit.edge.leaf, hit.index),
    );
    _draggedHingeEdge = hit.edge;
    _draggedHingeIndex = hit.index;
    _isDraggingHinge = true;
    _propertyDragHistorySaved = false;
    return true;
  }

  void _dragHingeTo(Offset local) {
    final edge = _draggedHingeEdge;
    if (edge == null) return;
    if (!_propertyDragHistorySaved) {
      widget.model.saveSnapshotOutside();
      _propertyDragHistorySaved = true;
    }
    widget.model.moveHinge(
      edge.zoneId,
      edge.leaf,
      _draggedHingeIndex,
      edge.positionAt(_getModelPos(local)),
      edge.length,
    );
  }

  SashHingeEdge? get _selectedHingeEdge {
    final selected = widget.model.selectedHinge;
    if (selected == null) return null;
    final edge = widget.model.hingeEdgeOf(selected.zoneId, selected.leaf);
    if (edge == null || selected.index >= _currentHinges(edge).length) {
      return null;
    }
    return edge;
  }

  /// Positions straight from the model: the painted edge may be one frame
  /// behind right after an edit.
  List<double> _currentHinges(SashHingeEdge edge) {
    for (final zone in widget.model.zones) {
      if (zone.id == edge.zoneId) {
        return widget.model.hingePositionsFor(zone, edge.leaf, edge.length);
      }
    }
    return const [];
  }

  void _addHingeTo(SashHingeEdge edge, {double? near}) {
    _showHingeMessage(
      widget.model.addHinge(edge.zoneId, edge.leaf, edge.length, near: near),
    );
  }

  void _removeSelectedHinge() {
    final selected = widget.model.selectedHinge;
    final edge = _selectedHingeEdge;
    if (selected == null || edge == null) return;
    _showHingeMessage(
      widget.model.removeHinge(
        edge.zoneId,
        edge.leaf,
        selected.index,
        edge.length,
      ),
    );
  }

  void _resetHingesOf(SashHingeEdge edge) {
    widget.model.resetHinges(edge.zoneId, leaf: edge.leaf);
    widget.model.selectHinge(null);
  }

  void _showHingeMessage(String? key) {
    if (key == null || !mounted) return;
    final text = _tr(key)
        .replaceAll(
          '{min}',
          SashHingeRules.minEndDistanceMm.round().toString(),
        )
        .replaceAll('{gap}', SashHingeRules.minSpacingMm.round().toString());
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(text),
          backgroundColor: Colors.orange.shade800,
          duration: const Duration(seconds: 3),
          behavior: SnackBarBehavior.floating,
        ),
      );
  }

  /// Right click on a hinge or on a hinged edge. Returns false when the
  /// click was elsewhere, so the normal context menu opens.
  Future<bool> _showHingeContextMenu(Offset global, Offset local) async {
    final hit = _hingeAt(local);
    final edgeHit = hit == null ? _hingeEdgeAt(local) : null;
    final edge = hit?.edge ?? edgeHit?.edge;
    if (edge == null) return false;
    if (hit != null) _selectHinge(hit);
    if (!edge.editable) return true;

    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final action = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromLTWH(global.dx, global.dy, 1, 1),
        Offset.zero & overlay.size,
      ),
      items: [
        PopupMenuItem(
          value: 'add',
          child: _hingeMenuRow(Icons.add_circle_outline, 'إضافة مفصل هنا'),
        ),
        if (hit != null)
          PopupMenuItem(
            value: 'remove',
            child: _hingeMenuRow(Icons.delete_outline, 'حذف المفصل'),
          ),
        PopupMenuItem(
          value: 'reset',
          child: _hingeMenuRow(Icons.auto_fix_high, 'توزيع المفاصل تلقائياً'),
        ),
      ],
    );
    if (!mounted) return true;
    switch (action) {
      case 'add':
        _addHingeTo(
          edge,
          near: hit != null
              ? edge.positions[hit.index]
              : edgeHit?.position,
        );
      case 'remove':
        _removeSelectedHinge();
      case 'reset':
        _resetHingesOf(edge);
    }
    return true;
  }

  Widget _hingeMenuRow(IconData icon, String label) => Row(
    mainAxisSize: MainAxisSize.min,
    children: [
      Icon(icon, size: 18),
      const SizedBox(width: 10),
      Text(_tr(label), style: const TextStyle(fontSize: 13)),
    ],
  );

  Future<void> _showHingePositionDialog(
    SashHingeEdge edge,
    SelectedHinge selected,
  ) async {
    final positions = _currentHinges(edge);
    if (selected.index < 0 || selected.index >= positions.length) return;
    final gap = SashHingeRules.nearestGap(
      positions,
      selected.index,
      edge.length,
    );
    final currentDistance = gap.to - gap.from;
    final controller = TextEditingController(
      text: currentDistance.toStringAsFixed(
        currentDistance == currentDistance.roundToDouble() ? 0 : 1,
      ),
    );
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    final requestedDistance = await showDialog<double>(
      context: context,
      builder: (dialogContext) {
        String? errorText;
        return StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(Localization.translate('تغيير مكان المفصل', lang)),
            content: TextField(
              controller: controller,
              autofocus: true,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'المسافة إلى أقرب مفصل أو طرف (مم)',
                  lang,
                ),
                suffixText: 'mm',
                errorText: errorText,
                border: const OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                final value = double.tryParse(
                  controller.text.trim().replaceAll(',', '.'),
                );
                if (value == null || value <= 0) {
                  setDialogState(
                    () => errorText = Localization.translate(
                      'أدخل مسافة صحيحة أكبر من الصفر',
                      lang,
                    ),
                  );
                  return;
                }
                Navigator.pop(dialogContext, value);
              },
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(Localization.translate('إلغاء', lang)),
              ),
              FilledButton(
                onPressed: () {
                  final value = double.tryParse(
                    controller.text.trim().replaceAll(',', '.'),
                  );
                  if (value == null || value <= 0) {
                    setDialogState(
                      () => errorText = Localization.translate(
                        'أدخل مسافة صحيحة أكبر من الصفر',
                        lang,
                      ),
                    );
      return;
    }
                  Navigator.pop(dialogContext, value);
                },
                child: Text(Localization.translate('تطبيق', lang)),
              ),
            ],
          ),
        );
      },
    );
    controller.dispose();
    if (!mounted || requestedDistance == null) return;

    final latestPositions = _currentHinges(edge);
    if (selected.index < 0 || selected.index >= latestPositions.length) return;
    final latestGap = SashHingeRules.nearestGap(
      latestPositions,
      selected.index,
      edge.length,
    );
    final selectedPosition = latestPositions[selected.index];
    final selectedIsLowerEnd =
        (selectedPosition - latestGap.from).abs() < 0.5;
    final target = selectedIsLowerEnd
        ? latestGap.to - requestedDistance
        : latestGap.from + requestedDistance;
    _showHingeMessage(
      widget.model.moveHinge(
        edge.zoneId,
        edge.leaf,
        selected.index,
        target,
        edge.length,
        saveHistory: true,
        snapToGrid: false,
      ),
    );
  }

  /// Small bar next to the selected hinge: its position, add, delete and
  /// back to the automatic layout. Hidden while the hinge is being dragged.
  Widget? _buildHingeToolbar(BoxConstraints constraints) {
    final selected = widget.model.selectedHinge;
    final edge = _selectedHingeEdge;
    if (selected == null || edge == null || _draggedHingeEdge != null) {
      return null;
    }
    final positions = _currentHinges(edge);
    final center = _modelToScreen(edge.pointAt(positions[selected.index]));
    final barWidth = math.min(560.0, math.max(220.0, constraints.maxWidth - 16));
    const barHeight = 52.0;
    final left = (center.dx - barWidth / 2)
        .clamp(8.0, math.max(8.0, constraints.maxWidth - barWidth - 8))
        .toDouble();
    var top = center.dy - _hingeHitRadiusPx - barHeight - 8;
    if (top < 8) top = center.dy + _hingeHitRadiusPx + 8;
    top = top
        .clamp(8.0, math.max(8.0, constraints.maxHeight - barHeight - 8))
        .toDouble();
    final count = positions.length;
    final gap = SashHingeRules.nearestGap(
      positions,
      selected.index,
      edge.length,
    );
    final position = (gap.to - gap.from).round();
    final isDark = Theme.of(context).brightness == Brightness.dark;

    Widget button(
      IconData icon,
      String label,
      VoidCallback? onTap,
    ) => TextButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(_tr(label), style: const TextStyle(fontSize: 11)),
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 7),
        visualDensity: VisualDensity.compact,
      ),
    );

    return Positioned(
      left: left,
      top: top,
      width: barWidth,
      height: barHeight,
      child: Material(
        elevation: 6,
        borderRadius: BorderRadius.circular(10),
        color: isDark ? const Color(0xFF2E2E40) : Colors.white,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              Tooltip(
                message: _tr('اضغط لتغيير مسافة المفصل'),
                child: TextButton.icon(
                  onPressed: edge.editable
                      ? () => _showHingePositionDialog(edge, selected)
                      : null,
                  icon: Icon(
                    edge.vertical ? Icons.height : Icons.swap_horiz_rounded,
                  ),
                  label: Text(
                    '$position mm · $count ${_tr('مفصل')}',
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),
              if (edge.editable) ...[
                button(
                  Icons.add_circle_outline,
                  'إضافة مفصل',
                  () => _addHingeTo(edge),
                ),
                button(
                  Icons.delete_outline,
                  'حذف مفصل',
                  count > SashHingeRules.minCount
                      ? _removeSelectedHinge
                      : null,
                ),
                button(
                  Icons.auto_fix_high,
                  'توزيع تلقائي',
                  () => _resetHingesOf(edge),
                ),
              ],
              button(
                Icons.close,
                'إغلاق',
                () => widget.model.selectHinge(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  bool _isTopZone(WindowZone zone) {
    if (widget.model.zones.isEmpty) return false;
    double minTop = widget.model.zones
        .map((z) => z.boundary.top)
        .reduce(math.min);
    return zone.boundary.top == minTop;
  }

  // Same head geometry as WindowPainter (model.headEdgeY), so hit tests on
  // handles and divisions under a slanted or arched head match the drawing.
  double getInnerTopY(double x, double t, double topOffset) =>
      widget.model.headEdgeY(x, t, topOffset: topOffset);

  double getSashTopY(
    double x,
    double sashTopFlat,
    double t,
    double topOffset,
    bool isTopBound,
  ) {
    if (!isTopBound) return sashTopFlat;
    return widget.model.headEdgeY(
      x,
      math.max(t, sashTopFlat - topOffset),
      topOffset: topOffset,
    );
  }

  bool _checkAndStartSashDividerDrag(
    String zoneId,
    bool isRight,
    Rect glassR,
    int innerH,
    int innerV,
    List<double> innerHPos,
    List<double> innerVPos,
    Offset touchScreen,
  ) {
    if (innerH == 0 && innerV == 0) return false;

    // 🟢 تكبير مساحة التقاط اللمس لتسهيل التحديد والتحريك (Hit Slop)
    final double hitRadius = 50.0; // كانت 30.0

    List<double> hPositions = List.from(innerHPos);
    if (hPositions.isEmpty && innerH > 0) {
      double stepY = 1.0 / (innerH + 1);
      for (int i = 1; i <= innerH; i++) {
        hPositions.add(stepY * i);
      }
    }
    List<double> vPositions = List.from(innerVPos);
    if (vPositions.isEmpty && innerV > 0) {
      double stepX = 1.0 / (innerV + 1);
      for (int i = 1; i <= innerV; i++) {
        vPositions.add(stepX * i);
      }
    }
    final zone = widget.model.zones.firstWhere(
      (candidate) => candidate.id == zoneId,
      orElse: () => WindowZone(
        id: zoneId,
        boundary: Rect.zero,
        sashColor: widget.model.frameColor,
      ),
    );
    String getVKey(int r, int v) => isRight ? 'right_${r}_$v' : '${r}_$v';
    String getHKey(int c, int h) => isRight ? 'right_${c}_$h' : '${c}_$h';

    // Check horizontal dividers
    for (int i = 0; i < hPositions.length; i++) {
      double yVal = glassR.top + glassR.height * hPositions[i];
      for (int c = 0; c < vPositions.length + 1; c++) {
        if (zone.disabledHorizontalDivisions[getHKey(c, i)] == true) {
          continue;
        }
        final leftRatio = c == 0 ? 0.0 : vPositions[c - 1];
        final rightRatio = c == vPositions.length ? 1.0 : vPositions[c];
        final lineStart = _modelToScreen(
          Offset(glassR.left + glassR.width * leftRatio, yVal),
        );
        final lineEnd = _modelToScreen(
          Offset(glassR.left + glassR.width * rightRatio, yVal),
        );
        final screenY = lineStart.dy;
        final screenLeft = math.min(lineStart.dx, lineEnd.dx);
        final screenRight = math.max(lineStart.dx, lineEnd.dx);

        if ((touchScreen.dy - screenY).abs() < hitRadius &&
            touchScreen.dx >= screenLeft - hitRadius &&
            touchScreen.dx <= screenRight + hitRadius) {
          _setViewState(() {
            _isDraggingSashDivision = true;
            _draggedSashZoneId = zoneId;
            _draggedSashIsRight = isRight;
            _draggedSashIsHorizontal = true;
            _draggedSashIndex = i;
          });
          widget.model.selection = SelectionInfo(
            type: SelectionType.innerDivision,
            zoneId: zoneId,
            isHorizontalInnerDivision: true,
            isRightSashInnerDivision: isRight,
            innerDivisionIndex: i,
          );
          widget.model.showZoneMenu = false;
          widget.model.activeSubZone = null;
          widget.model.refreshUI();
          return true;
        }
      }
    }

    // Check vertical dividers
    for (int i = 0; i < vPositions.length; i++) {
      double xVal = glassR.left + glassR.width * vPositions[i];
      for (int r = 0; r < hPositions.length + 1; r++) {
        if (zone.disabledVerticalDivisions[getVKey(r, i)] == true) {
          continue;
        }
        final topRatio = r == 0 ? 0.0 : hPositions[r - 1];
        final bottomRatio = r == hPositions.length ? 1.0 : hPositions[r];
        final lineStart = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * topRatio),
        );
        final lineEnd = _modelToScreen(
          Offset(xVal, glassR.top + glassR.height * bottomRatio),
        );
        final screenX = lineStart.dx;
        final screenTop = math.min(lineStart.dy, lineEnd.dy);
        final screenBottom = math.max(lineStart.dy, lineEnd.dy);

        if ((touchScreen.dx - screenX).abs() < hitRadius &&
            touchScreen.dy >= screenTop - hitRadius &&
            touchScreen.dy <= screenBottom + hitRadius) {
          _setViewState(() {
            _isDraggingSashDivision = true;
            _draggedSashZoneId = zoneId;
            _draggedSashIsRight = isRight;
            _draggedSashIsHorizontal = false;
            _draggedSashIndex = i;
          });
          widget.model.selection = SelectionInfo(
            type: SelectionType.innerDivision,
            zoneId: zoneId,
            isHorizontalInnerDivision: false,
            isRightSashInnerDivision: isRight,
            innerDivisionIndex: i,
          );
          widget.model.showZoneMenu = false;
          widget.model.activeSubZone = null;
          widget.model.refreshUI();
          return true;
        }
      }
    }

    return false;
  }

  void _startDrawingTimer() {
    _drawingTimer?.cancel();
    widget.model.setDrawingMode(true);
    if (_isWindowsDesktop) return;
    _drawingTimer = Timer(const Duration(seconds: 10), () {
      if (mounted) {
        widget.model.setDrawingMode(false);
      }
    });
  }

  void _stopDrawingTimer() {
    _drawingTimer?.cancel();
    // Windows has no move mode: the drawing stays editable.
    widget.model.setDrawingMode(_isWindowsDesktop);
  }

  Offset _getModelPos(Offset screenPos) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      (screenPos.dx - widget.model.canvasDx - _userPan.dx) / totalScale,
      (screenPos.dy - widget.model.canvasDy - _userPan.dy) / totalScale,
    );
  }

  Offset _modelToScreen(Offset modelPosition) {
    final totalScale = widget.model.canvasScale * _userScale;
    return Offset(
      widget.model.canvasDx + _userPan.dx + modelPosition.dx * totalScale,
      widget.model.canvasDy + _userPan.dy + modelPosition.dy * totalScale,
    );
  }

  void _changeDrawingZoom(double factor, Offset focalPoint) {
    final double nextScale = (_userScale * factor).clamp(
      _WindowViewState._minUserScale,
      _WindowViewState._maxUserScale,
    );
    if (nextScale == _userScale) return;

    _setViewState(() {
      final scaleRatio = nextScale / _userScale;
      // canvasDx/canvasDy are applied before the user zoom.  Keeping them in
      // this equation makes the focal point truly stationary instead of
      // pulling the drawing towards the top-left on every zoom step.
      final canvasOrigin = Offset(widget.model.canvasDx, widget.model.canvasDy);
      _userPan =
          focalPoint -
          canvasOrigin -
          (focalPoint - canvasOrigin - _userPan) * scaleRatio;
      _userScale = nextScale;
    });
  }

  void _handleDrawingPointerSignal(PointerSignalEvent event) {
    if (!_isWindowsDesktop || event is! PointerScrollEvent) return;
    final verticalDelta = event.scrollDelta.dy;
    if (verticalDelta == 0) return;

    GestureBinding.instance.pointerSignalResolver.register(event, (_) {
      if (!mounted) return;
      _changeDrawingZoom(
        verticalDelta < 0 ? _WindowViewState._zoomStep : 1 / _WindowViewState._zoomStep,
        _drawingViewportCenter(),
      );
    });
  }

  void _resetDrawingZoom() {
    _setViewState(() {
      _userScale = 1.0;
      _userPan = Offset.zero;
    });
    // The drawing stays where it was created until the user explicitly asks
    // to centre it using this control.
    widget.model.centerDrawingOnCanvas();
  }

  Offset _drawingViewportCenter() {
    final size = widget.model.lastLayoutSize;
    if (size == null) return Offset.zero;
    return Offset(size.width / 2, size.height / 2);
  }

  Rect? _dimensionTextBounds(
    String text,
    Rect bounds, {
    bool vertical = false,
  }) {
    final crossAxis = vertical ? bounds.width : bounds.height;
    final mainAxis = vertical ? bounds.height : bounds.width;
    if (crossAxis < 12 || mainAxis < 35) return null;

    double fontSize = math.min(34.0, math.max(15.0, crossAxis * 0.78));
    late TextPainter painter;
    while (true) {
      painter = TextPainter(
        text: TextSpan(
          text: text,
          style: TextStyle(fontSize: fontSize, fontWeight: FontWeight.w800),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      if (painter.width <= mainAxis - 8 || fontSize <= 10) break;
      fontSize -= 1.0;
    }
    if (painter.width > mainAxis - 4) return null;

    return vertical
        ? Rect.fromCenter(
            center: bounds.center,
            width: painter.height + 6,
            height: painter.width + 8,
          )
        : Rect.fromCenter(
            center: bounds.center,
            width: painter.width + 8,
            height: painter.height + 6,
          );
  }

  /// Hit-test only the visible number written in the selected frame profile.
  /// The remaining profile area stays available for selecting the frame.
  InnerDimensionHit? _frameProfileDimensionHit(Offset modelPosition) {
    if (widget.model.zones.length < 2) return null;
    final thickness = widget.model.profileThickness;
    final showWidthInside = widget.model.getVerticalFrameJoints().isEmpty;
    final showHeightInside = widget.model.getHorizontalFrameJoints().isEmpty;
    final frameRects = widget.model.getFrameRects();
    for (final outer in frameRects.reversed) {
      WindowZone? representativeZone;
      final inner = outer.deflate(thickness);
      for (final zone in widget.model.zones) {
        if (inner.overlaps(zone.boundary) ||
            inner.contains(zone.boundary.center)) {
          representativeZone = zone;
          break;
        }
      }
      if (representativeZone == null) continue;
      if (showWidthInside) {
        final widthBounds = Rect.fromLTWH(
          outer.left + 2,
          outer.top + 1,
          math.max(0.0, outer.width - 4),
          math.max(0.0, thickness - 2),
        );
        final widthText = _dimensionTextBounds(
          '${outer.width.toInt()}',
          widthBounds,
        );
        if (widthText?.contains(modelPosition) == true) {
          return InnerDimensionHit(representativeZone.id, true);
        }
      }

      if (showHeightInside) {
        final heightBounds = Rect.fromLTWH(
          outer.left + 1,
          outer.top + 2,
          math.max(0.0, thickness - 2),
          math.max(0.0, outer.height - 4),
        );
        final heightText = _dimensionTextBounds(
          '${outer.height.toInt()}',
          heightBounds,
          vertical: true,
        );
        if (heightText?.contains(modelPosition) == true) {
          return InnerDimensionHit(representativeZone.id, false);
        }
      }
    }
    return null;
  }

  void _toggleDrawingInteractionMode() {
    if (widget.model.isDrawingMode) {
      _stopDrawingTimer();
    } else {
      _startDrawingTimer();
    }
    _setViewState(() {});
  }

  String _shownDimensionText(double value) {
    final rounded = (value * 10).round() / 10;
    return (rounded - rounded.round()).abs() < 0.001
        ? rounded.round().toString()
        : rounded.toStringAsFixed(1);
  }
}
