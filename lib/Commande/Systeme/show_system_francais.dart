import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:database_data/Commande/window_painter.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/cutting_calculator.dart';

class WindowView extends StatefulWidget {
  final WindowModel model;
  final String systemMode;

  const WindowView({super.key, required this.model, this.systemMode = ''});

  @override
  State<WindowView> createState() => _WindowViewState();
}

class _WindowViewState extends State<WindowView> {
  bool _isDraggingHandle = false;

  Color _getFrameColorDisplay(FrameColor c) {
    switch (c) {
      case FrameColor.white:
        return Colors.white;
      case FrameColor.brown:
        return const Color(0xFF5D4037);
      case FrameColor.gray:
        return Colors.grey;
      case FrameColor.black:
        return Colors.black87;
      case FrameColor.beige:
        return const Color(0xFFDDC8A0);
    }
  }

  void _handleHandleDrag(DragUpdateDetails details, WindowZone zone) {
    if (zone.openDirection == null) return;
    double dx = details.delta.dx / widget.model.canvasScale;
    double dy = details.delta.dy / widget.model.canvasScale;
    double newRatio = zone.handlePositionRatio ?? 0.5;
    if (zone.openDirection == OpenDirection.top ||
        zone.openDirection == OpenDirection.bottom) {
      newRatio += (dx / zone.boundary.width);
    } else {
      newRatio -= (dy / zone.boundary.height);
    }
    widget.model.updateHandlePosition(zone.id, newRatio.clamp(0.1, 0.9));
  }

  void _showMullionResizeDialog(BuildContext context, int section) {
    bool isH = widget.model.selection.isHorizontalMullion!;
    double pos = widget.model.selection.mullionPosition!;
    final t = widget.model.profileThickness;
    double currentValue = isH
        ? (section == 1
              ? (pos - t * 1.5)
              : (widget.model.height - pos - t * 1.5))
        : (section == 1
              ? (pos - t * 1.5)
              : (widget.model.width - pos - t * 1.5));
    final ctrl = TextEditingController(text: currentValue.toInt().toString());
    showDialog(
      context: context,
      builder: (context) {
        String label = isH
            ? (section == 1
                  ? 'تعديل الفراغ العلوي (mm)'
                  : 'تعديل الفراغ السفلي (mm)')
            : (section == 1
                  ? 'تعديل الفراغ الأيسر (mm)'
                  : 'تعديل الفراغ الأيمن (mm)');
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            label,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              labelText: 'البُعد الصافي للفراغ (mm)',
              labelStyle: TextStyle(color: Colors.grey),
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blueGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val > 0) {
                  widget.model.resizeMullionDimension(section, val);
                }
                Navigator.pop(context);
              },
              child: const Text(
                'تطبيق القياس الجديد',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  void initState() {
    super.initState();
    // 🟢 نطلب جلب الكتالوجات بمجرد فتح الشاشة
    widget.model.loadCatalogData(widget.systemMode);
  }

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: widget.model,
      builder: (context, _) {
        final hasSelection = widget.model.selectedZone != null;
        final isMullionSelected =
            widget.model.selection.type == SelectionType.mullion;

        return Scaffold(
          backgroundColor: const Color(0xFFE8EAF6),
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              _buildGlobalSettingsBar(context),
              buildShutterSidesControl(context, widget.model),
              if (!isMullionSelected) _buildSplitToolbar(context, hasSelection),
              if (hasSelection &&
                  !isMullionSelected &&
                  widget.model.showZoneMenu)
                _buildContentToolbar(context),
              if (isMullionSelected) _buildMullionToolbar(context),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    // 🟢 حساب أبعاد ومقياس الشاشة ليتوافق مع الرسم بدقة
                    widget.model.updateLayoutMetrics(
                      Size(constraints.maxWidth, constraints.maxHeight),
                    );

                    return GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTapUp: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );

                        final outerTap = widget.model.checkOuterDimensionTap(
                          modelPos,
                        );
                        if (outerTap != DimensionTap.none) {
                          _showResizeDialog(
                            context,
                            focusWidth: outerTap == DimensionTap.width,
                          );
                          return;
                        }

                        final innerTap = widget.model.checkInnerDimensionTap(
                          modelPos,
                        );
                        if (innerTap != null) {
                          _showInnerResizeDialog(context, innerTap);
                          return;
                        }

                        final mullionDimTap = widget.model
                            .checkMullionDimensionTap(modelPos);
                        if (mullionDimTap != null) {
                          _showMullionResizeDialog(context, mullionDimTap);
                          return;
                        }

                        widget.model.selectAt(modelPos, isLongPress: false);
                      },
                      onLongPressStart: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );
                        widget.model.selectAt(modelPos, isLongPress: true);
                      },
                      onPanStart: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );
                        if (widget.model.isDrawingMode &&
                            widget.model.selection.type !=
                                SelectionType.mullion) {
                          widget.model.startDrawing(modelPos);
                        } else if (widget.model.selectedZone != null &&
                            widget.model.selectedZone!.boundary.contains(
                              modelPos,
                            )) {
                          _isDraggingHandle = true;
                        }
                      },
                      onPanUpdate: (details) {
                        final modelPos = Offset(
                          (details.localPosition.dx - widget.model.canvasDx) /
                              widget.model.canvasScale,
                          (details.localPosition.dy - widget.model.canvasDy) /
                              widget.model.canvasScale,
                        );
                        if (widget.model.drawingStart != null) {
                          widget.model.updateDrawing(modelPos);
                        } else if (widget.model.selection.type ==
                                SelectionType.mullion &&
                            !widget.model.isDrawingMode) {
                          widget.model.moveSelectedMullion(
                            (widget.model.selection.isHorizontalMullion!
                                    ? details.delta.dy
                                    : details.delta.dx) /
                                widget.model.canvasScale,
                          );
                        } else if (_isDraggingHandle &&
                            widget.model.selectedZone != null) {
                          _handleHandleDrag(
                            details,
                            widget.model.selectedZone!,
                          );
                        }
                      },
                      onPanEnd: (details) {
                        if (widget.model.drawingStart != null) {
                          widget.model.endDrawing();
                        }
                        _isDraggingHandle = false;
                      },
                      onPanCancel: () {
                        _isDraggingHandle = false;
                      },
                      child: Container(
                        width: double.infinity,
                        height: double.infinity,
                        decoration: const BoxDecoration(
                          color: Color(0xFFF5F5F5),
                        ),
                        // 🟢 استدعاء رسام مساحة العمل الجديد ليدير الزوم بشكل صحيح
                        child: CustomPaint(
                          size: Size(
                            constraints.maxWidth,
                            constraints.maxHeight,
                          ),
                          painter: AppWorkspacePainter(model: widget.model),
                        ),
                      ),
                    );
                  },
                ),
              ),
              _buildStatusBar(context),
            ],
          ),
        );
      },
    );
  }

  void _showInnerResizeDialog(BuildContext context, InnerDimensionHit hit) {
    final zone = widget.model.zones.firstWhere((z) => z.id == hit.zoneId);
    final currentValue = hit.isWidth
        ? zone.boundary.width
        : zone.boundary.height;
    final ctrl = TextEditingController(text: currentValue.toInt().toString());

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: Text(
            hit.isWidth ? 'تعديل عرض التقسيم' : 'تعديل ارتفاع التقسيم',
            style: const TextStyle(color: Colors.black, fontSize: 18),
          ),
          content: TextField(
            controller: ctrl,
            autofocus: true,
            keyboardType: TextInputType.number,
            style: const TextStyle(
              color: Colors.black,
              fontSize: 20,
              fontWeight: FontWeight.bold,
            ),
            decoration: const InputDecoration(
              labelText: 'القياس الداخلي (mm)',
              enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blueGrey),
              ),
              focusedBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.blue, width: 2),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final val = double.tryParse(ctrl.text);
                if (val != null && val >= 50) {
                  widget.model.resizeZoneInner(hit.zoneId, hit.isWidth, val);
                }
                Navigator.pop(context);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  void _showResizeDialog(BuildContext context, {required bool focusWidth}) {
    final widthCtrl = TextEditingController(
      text: widget.model.width.toInt().toString(),
    );
    final heightCtrl = TextEditingController(
      text: widget.model.height.toInt().toString(),
    );
    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          title: const Text(
            'تعديل قياسات النافذة',
            style: TextStyle(color: Colors.black, fontSize: 18),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: widthCtrl,
                  autofocus: focusWidth,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'العرض الإجمالي (mm)',
                  ),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: heightCtrl,
                  autofocus: !focusWidth,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  decoration: const InputDecoration(
                    labelText: 'الارتفاع الإجمالي (mm)',
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () {
                final w = double.tryParse(widthCtrl.text) ?? widget.model.width;
                final h =
                    double.tryParse(heightCtrl.text) ?? widget.model.height;
                if (w >= widget.model.profileThickness * 3 &&
                    h >= widget.model.profileThickness * 3) {
                  widget.model.resizeWindow(w, h);
                }
                Navigator.pop(context);
              },
              child: const Text('تطبيق', style: TextStyle(color: Colors.white)),
            ),
          ],
        );
      },
    );
  }

  Widget _buildMullionToolbar(BuildContext context) {
    String key =
        "${widget.model.selection.isHorizontalMullion! ? 'H' : 'V'}_${widget.model.selection.mullionPosition!.toStringAsFixed(1)}";
    MullionProfileType currentType =
        widget.model.mullionProfiles[key] ?? MullionProfileType.standard;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: Colors.blue.shade900.withValues(alpha: 0.8),
      child: Row(
        children: [
          const Icon(Icons.drag_indicator_rounded, color: Colors.white),
          const SizedBox(width: 10),
          const Text(
            'العمود محدد',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          ),
          const Spacer(),
          DropdownButton<MullionProfileType>(
            dropdownColor: Colors.blue.shade800,
            value: currentType,
            style: const TextStyle(color: Colors.white, fontSize: 13),
            underline: Container(height: 1, color: Colors.white38),
            icon: const Icon(Icons.arrow_drop_down, color: Colors.white),
            items: const [
              DropdownMenuItem(
                value: MullionProfileType.standard,
                child: Text('Traverse'),
              ),
              DropdownMenuItem(
                value: MullionProfileType.flat,
                child: Text('Cadre doublé'),
              ),
              DropdownMenuItem(
                value: MullionProfileType.grooved,
                child: Text('Cadre 140'),
              ),
            ],
            onChanged: (val) {
              if (val != null) widget.model.setMullionProfile(val);
            },
          ),
          const SizedBox(width: 15),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red.shade600,
            ),
            icon: const Icon(Icons.delete_sweep, color: Colors.white, size: 18),
            label: const Text('حذف', style: TextStyle(color: Colors.white)),
            onPressed: () => widget.model.deleteSelectedMullion(),
          ),
        ],
      ),
    );
  }

  Widget buildShutterSidesControl(BuildContext context, WindowModel model) {
    if (!model.hasSideCovers && !model.hasShutter) {
      return const SizedBox.shrink();
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Padding(
          padding: EdgeInsets.all(8.0),
          child: Text(
            "تخصيص جهات الغطاء الجانبي:",
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
        ),
        Wrap(
          spacing: 8.0,
          children: [
            FilterChip(
              label: const Text("العلوية"),
              selected: !model.removedShutterSides.contains('top'),
              onSelected: (_) => model.toggleShutterSide('top'),
            ),
            FilterChip(
              label: const Text("اليسرى"),
              selected: !model.removedShutterSides.contains('left'),
              onSelected: (_) => model.toggleShutterSide('left'),
            ),
            FilterChip(
              label: const Text("اليمنى"),
              selected: !model.removedShutterSides.contains('right'),
              onSelected: (_) => model.toggleShutterSide('right'),
            ),
            FilterChip(
              label: const Text("السفلية"),
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

  Widget _buildGlobalSettingsBar(BuildContext context) {
    return Container(
      height: 95,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: Colors.white,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'لون الألمنيوم',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.grey.shade300),
                  ),
                  child: Row(
                    children: FrameColor.values.map((color) {
                      final isSelected = widget.model.frameColor == color;
                      return GestureDetector(
                        onTap: () => widget.model.frameColor = color,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          margin: const EdgeInsets.symmetric(horizontal: 4),
                          width: isSelected ? 26 : 22,
                          height: isSelected ? 26 : 22,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _getFrameColorDisplay(color),
                            border: Border.all(
                              color: isSelected
                                  ? Colors.blue
                                  : Colors.grey.shade400,
                              width: isSelected ? 2.5 : 1.0,
                            ),
                            boxShadow: isSelected
                                ? [
                                    BoxShadow(
                                      color: Colors.blue.withValues(alpha: 0.3),
                                      blurRadius: 4,
                                      spreadRadius: 1,
                                    ),
                                  ]
                                : [],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ],
            ),
            const SizedBox(width: 15),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'إطار سفلي',
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                Switch(
                  value: widget.model.hasBottomFrame,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleBottomFrame(value),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'غطاء جانبي',
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                Switch(
                  value: widget.model.hasSideCovers,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleSideCovers(value),
                ),
              ],
            ),
            const SizedBox(width: 10),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: const Icon(Icons.texture),
                  tooltip: 'تحويل زجاج / بانو',
                  color:
                      (widget.model.selectedZone != null &&
                          (widget.model.activeSubZone?.contains('cell_') ==
                                  true ||
                              widget.model.selectedZone!.content ==
                                  ZoneContent.fixedGlass ||
                              widget.model.selectedZone!.content ==
                                  ZoneContent.empty))
                      ? Colors.blue
                      : Colors.grey,
                  onPressed: () {
                    if (widget.model.selectedZone != null) {
                      widget.model.toggleSelectedCellPanel();
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('الرجاء تحديد زجاج أو مربع أولاً!'),
                        ),
                      );
                    }
                  },
                ),
              ],
            ),
            Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text(
                  'ستار (Volet)',
                  style: TextStyle(color: Colors.black54, fontSize: 11),
                ),
                Switch(
                  value: widget.model.hasShutter,
                  activeThumbColor: Colors.blue,
                  onChanged: (value) => widget.model.toggleShutter(value),
                ),
              ],
            ),
            if (widget.model.hasShutter)
              SizedBox(
                width: 150,
                child: Row(
                  children: [
                    const SizedBox(width: 10),
                    Expanded(
                      child: Slider(
                        value: widget.model.shutterPosition,
                        min: 0.0,
                        max: 1.0,
                        activeColor: Colors.blue,
                        inactiveColor: Colors.grey.shade300,
                        onChanged: (value) =>
                            widget.model.setShutterPosition(value),
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 15),
            GestureDetector(
              onTap: () => widget.model.toggleViewMode(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: widget.model.isInternalView
                      ? Colors.blue.shade50
                      : Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: widget.model.isInternalView
                        ? Colors.blue
                        : Colors.orange,
                    width: 1.5,
                  ),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      widget.model.isInternalView
                          ? Icons.visibility
                          : Icons.flip_camera_android,
                      size: 20,
                      color: widget.model.isInternalView
                          ? Colors.blue.shade900
                          : Colors.orange.shade900,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.model.isInternalView ? 'وجه داخلي' : 'وجه خارجي',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                        color: widget.model.isInternalView
                            ? Colors.blue.shade900
                            : Colors.orange.shade900,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black,
      elevation: 0.5,
      titleSpacing: 8,
      // 🟢 السر هنا: وضعنا كل شيء داخل SingleChildScrollView لكي يختفي الأوفر فلو نهائياً
      title: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'تصميم النوافذ',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            const SizedBox(width: 12),

            // القائمة المنسدلة
            if (widget.model.availableSystems.isNotEmpty)
              Container(
                constraints: const BoxConstraints(maxWidth: 120),
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 0),
                decoration: BoxDecoration(
                  color: Colors.blue.shade50,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.blue.shade200),
                ),
                child: DropdownButton<AluminumSeries>(
                  isExpanded: true,
                  // يختصر النص الطويل بنقاط
                  value: widget.model.activeSeries,
                  hint: const Text(
                    'اختر السلسلة',
                    style: TextStyle(color: Colors.blue, fontSize: 12),
                  ),
                  underline: const SizedBox(),
                  icon: const Icon(
                    Icons.keyboard_arrow_down,
                    color: Colors.blue,
                    size: 18,
                  ),
                  items: widget.model.availableSystems.expand((system) {
                    return system.series.map((series) {
                      return DropdownMenuItem<AluminumSeries>(
                        value: series,
                        child: Text(
                          '${system.name} - ${series.name}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Colors.blue,
                            fontSize: 12,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    });
                  }).toList(),
                  onChanged: (AluminumSeries? newSeries) {
                    if (newSeries != null) {
                      widget.model.setActiveSeries(newSeries);
                    }
                  },
                ),
              ),

            const SizedBox(width: 8),

            // زر التراجع
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              onPressed: widget.model.canUndo ? widget.model.undo : null,
              icon: const Icon(Icons.undo_rounded),
              tooltip: 'تراجع',
              color: widget.model.canUndo ? Colors.black87 : Colors.black26,
            ),

            // زر وضع الرسم / التحريك
            IconButton(
              padding: const EdgeInsets.symmetric(horizontal: 4),
              constraints: const BoxConstraints(),
              icon: Icon(
                widget.model.isDrawingMode ? Icons.pan_tool : Icons.draw,
                color: widget.model.isDrawingMode ? Colors.orange : Colors.blue,
              ),
              tooltip: widget.model.isDrawingMode ? 'وضع التحريك' : 'وضع الرسم',
              onPressed: () {
                widget.model.toggleDrawingMode();
              },
            ),

            const SizedBox(width: 8),

            // 🟢 زر القياسات الجديد (يفتح نافذة التعديل عند الضغط عليه)
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade50,
                foregroundColor: Colors.blue.shade900,
                elevation: 0,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: const Size(0, 36),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                  side: BorderSide(color: Colors.blue.shade200),
                ),
              ),
              icon: const Icon(Icons.aspect_ratio_rounded, size: 16),
              label: Text(
                '${widget.model.width.toInt()} × ${widget.model.height.toInt()} mm',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              onPressed: () {
                // فتح نافذة التعديل
                _showResizeDialog(context, focusWidth: true);
              },
            ),
            const SizedBox(width: 8), // فراغ جمالي في نهاية السحب
          ],
        ),
      ),
      actions:
          const [], // أفرغنا هذا القسم لأن كل شيء أصبح قابلاً للسحب في الـ title
    );
  }

  Widget _buildSplitToolbar(BuildContext context, bool hasSelection) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      color: Colors.white,
      width: double.infinity,
      // 🟢 إضافة شريط التمرير الأفقي لحل مشكلة الأوفر فلو تماماً
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            const Text(
              'تقسيم:',
              style: TextStyle(
                color: Colors.black87,
                fontSize: 13,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 10),
            _ToolButton(
              icon: Icons.horizontal_split_rounded,
              label: 'أفقي',
              enabled: hasSelection,
              color: Colors.orange,
              onPressed: () {
                if (!hasSelection) return;
                _showSplitDialog(context, true);
              },
            ),
            const SizedBox(width: 8),
            _ToolButton(
              icon: Icons.vertical_split_rounded,
              label: 'عمودي',
              enabled: hasSelection,
              color: Colors.teal,
              onPressed: () {
                if (!hasSelection) return;
                _showSplitDialog(context, false);
              },
            ),
            const SizedBox(width: 15),
            // 🟢 زر وضع الرسم / وضع التحريك
            _ToolButton(
              icon: widget.model.isDrawingMode ? Icons.edit : Icons.pan_tool,
              label: widget.model.isDrawingMode
                  ? 'وضع الرسم (نشط)'
                  : 'وضع التحريك',
              enabled: true,
              color: widget.model.isDrawingMode
                  ? Colors.green.shade600
                  : Colors.blueGrey,
              onPressed: () => widget.model.toggleDrawingMode(),
            ),
            const SizedBox(width: 8), // فراغ أخير لجمالية السحب
          ],
        ),
      ),
    );
  }

  void _showCuttingListDialog(BuildContext context) {
    final List<CuttingItem> items = CuttingCalculator.calculate(widget.model);

    int singleCount = widget.model.zones
        .where((z) => z.content == ZoneContent.singleSash)
        .length;
    int doubleCount = widget.model.zones
        .where((z) => z.content == ZoneContent.doubleSash)
        .length;
    int totalSashes = singleCount + (doubleCount * 2);

    String handleInfo = 'غير متوفر';
    if (totalSashes > 0) {
      try {
        var activeZone = widget.model.zones.firstWhere(
          (z) =>
              z.content == ZoneContent.singleSash ||
              z.content == ZoneContent.doubleSash,
        );
        if (activeZone.handlePositionRatio != null) {
          double handleHeightFromBottom =
              activeZone.boundary.height *
              (1.0 - activeZone.handlePositionRatio!);
          handleInfo = '${handleHeightFromBottom.toInt()} mm من الأسفل';
        } else {
          handleInfo = 'في المنتصف';
        }
      } catch (e) {
        handleInfo = 'في المنتصف';
      }
    }

    String colorName = widget.model.selectedDbColor != null
        ? (widget.model.selectedDbColor!['name'] ?? 'افتراضي')
        : 'افتراضي';

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Row(
            children: const [
              Icon(Icons.content_cut, color: Colors.blue),
              SizedBox(width: 8),
              Text('قائمة التقطيع (سلسلة 60 - Frappe)'),
            ],
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Card(
                    color: Colors.grey.shade50,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      side: BorderSide(color: Colors.grey.shade300),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '🛠 مواصفات النافذة',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.blue.shade900,
                            ),
                          ),
                          const Divider(),
                          Text(
                            '• المقاس الكلي: ${widget.model.width.toInt()} × ${widget.model.height.toInt()} mm',
                          ),
                          Text('• عدد الدرف (Sashes): $totalSashes'),
                          Text(
                            '• سيتار (Volet): ${widget.model.hasShutter ? "نعم" : "لا"}',
                          ),
                          Text('• ارتفاع المقبض: $handleInfo'),
                          Text('• لون الألمنيوم: $colorName'),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  DataTable(
                    headingRowColor: WidgetStateProperty.all(
                      Colors.blue.shade50,
                    ),
                    columns: const [
                      DataColumn(
                        label: Text(
                          'النوع',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الوصف',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'العرض (mm)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الطول (mm)',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                      DataColumn(
                        label: Text(
                          'الكمية',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                    rows: items.map((item) {
                      return DataRow(
                        cells: [
                          DataCell(
                            Text(
                              item.type == CuttingItemType.glass
                                  ? "زجاج"
                                  : "ألمنيوم",
                            ),
                          ),
                          DataCell(Text(item.name)),
                          DataCell(Text(item.width.toStringAsFixed(1))),
                          DataCell(
                            Text(
                              item.height > 0
                                  ? item.height.toStringAsFixed(1)
                                  : '-',
                            ),
                          ),
                          DataCell(
                            Text(
                              item.quantity.toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        ],
                      );
                    }).toList(),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('إغلاق'),
            ),
          ],
        );
      },
    );
  }

  void _showSplitDialog(BuildContext context, bool isHorizontal) {
    final zone = widget.model.selectedZone;
    if (zone == null) return;

    // final isSash =
    //     zone.content == ZoneContent.doubleSash ||
    //     zone.content == ZoneContent.singleSash ||
    //     zone.content == ZoneContent.slidingSash;
    final double totalNetSize = isHorizontal
        ? zone.boundary.height - widget.model.profileThickness
        : zone.boundary.width - widget.model.profileThickness;

    int parts = 2;
    bool isEqualSplit = true;
    bool fromStart = true;
    TextEditingController part1Ctrl = TextEditingController();
    TextEditingController part2Ctrl = TextEditingController();

    String getRemainingText() {
      if (parts == 2) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        return 'المتبقي: ${(totalNetSize - p1).toStringAsFixed(1)} mm';
      } else if (parts == 3) {
        double p1 = double.tryParse(part1Ctrl.text) ?? 0;
        double p2 = double.tryParse(part2Ctrl.text) ?? 0;
        return 'القطعة الوسطى: ${(totalNetSize - p1 - p2).toStringAsFixed(1)} mm';
      }
      return '';
    }

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              title: Text(
                isHorizontal
                    ? 'تفاصيل التقسيم الأفقي'
                    : 'تفاصيل التقسيم العمودي',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.black,
                ),
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    RadioListTile<bool>(
                      title: const Text(
                        'تقسيم متساوي (حسب عدد القطع)',
                        style: TextStyle(
                          color: Colors.black,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      value: true,
                      groupValue: isEqualSplit,
                      onChanged: (v) => setState(() => isEqualSplit = v!),
                      activeColor: Colors.blue,
                    ),
                    RadioListTile<bool>(
                      title: const Text(
                        'قياس مخصص (إدخل الأبعاد)',
                        style: TextStyle(
                          color: Colors.black,
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
                    const Divider(),
                    if (isEqualSplit)
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'إلى كم قطعة تقسمها؟',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              color: Colors.black,
                            ),
                          ),
                          DropdownButton<int>(
                            value: parts,
                            dropdownColor: Colors.white,
                            style: const TextStyle(
                              color: Colors.black,
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                            items: List.generate(9, (index) => index + 2)
                                .map(
                                  (e) => DropdownMenuItem(
                                    value: e,
                                    child: Text('$e قطع'),
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
                              const Text(
                                'عدد القطع:',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black,
                                ),
                              ),
                              DropdownButton<int>(
                                value: parts,
                                dropdownColor: Colors.white,
                                style: const TextStyle(
                                  color: Colors.black,
                                  fontSize: 16,
                                  fontWeight: FontWeight.bold,
                                ),
                                items: [2, 3]
                                    .map(
                                      (e) => DropdownMenuItem(
                                        value: e,
                                        child: Text('$e قطع'),
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
                            'إجمالي القياس الصافي: ${totalNetSize.toStringAsFixed(1)} mm',
                            style: const TextStyle(
                              color: Colors.red,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 15),
                          if (parts == 2) ...[
                            Row(
                              children: [
                                const Text(
                                  'من أين يبدأ القياس؟ ',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: Colors.black,
                                  ),
                                ),
                                DropdownButton<bool>(
                                  value: fromStart,
                                  dropdownColor: Colors.white,
                                  style: const TextStyle(
                                    color: Colors.black,
                                    fontSize: 16,
                                  ),
                                  items: [
                                    DropdownMenuItem(
                                      value: true,
                                      child: Text(
                                        isHorizontal
                                            ? 'من الأعلى'
                                            : 'من اليسار',
                                      ),
                                    ),
                                    DropdownMenuItem(
                                      value: false,
                                      child: Text(
                                        isHorizontal
                                            ? 'من الأسفل'
                                            : 'من اليمين',
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
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: 'أدخل البُعد (mm)',
                                border: const OutlineInputBorder(),
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
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: isHorizontal
                                    ? 'القطعة العلوية (mm)'
                                    : 'القطعة اليسرى (mm)',
                                border: const OutlineInputBorder(),
                              ),
                              keyboardType: TextInputType.number,
                            ),
                            const SizedBox(height: 10),
                            TextField(
                              controller: part2Ctrl,
                              onChanged: (_) => setState(() {}),
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                              decoration: InputDecoration(
                                labelText: isHorizontal
                                    ? 'القطعة السفلية (mm)'
                                    : 'القطعة اليمنى (mm)',
                                border: const OutlineInputBorder(),
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
                        ? 'حذف التقسيم'
                        : 'إلغاء',
                    style: TextStyle(
                      color:
                          (zone.content != ZoneContent.empty &&
                              zone.content != ZoneContent.fixedGlass)
                          ? Colors.red
                          : Colors.grey,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
                  onPressed: () {
                    if (isEqualSplit) {
                      if (isHorizontal) {
                        widget.model.splitSelectedZoneHorizontal(parts: parts);
                      } else {
                        widget.model.splitSelectedZoneVertical(parts: parts);
                      }
                    } else {
                      List<double> customSizes = [];
                      if (parts == 2) {
                        double val =
                            double.tryParse(part1Ctrl.text) ??
                            (totalNetSize / 2);
                        customSizes.add(val);
                        if (isHorizontal) {
                          widget.model.splitSelectedZoneHorizontal(
                            parts: 2,
                            customSizes: customSizes,
                            fromTop: fromStart,
                          );
                        } else {
                          widget.model.splitSelectedZoneVertical(
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
                          widget.model.splitSelectedZoneHorizontal(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        } else {
                          widget.model.splitSelectedZoneVertical(
                            parts: 3,
                            customSizes: customSizes,
                          );
                        }
                      }
                    }
                    Navigator.pop(context);
                  },
                  child: const Text(
                    'تطبيق',
                    style: TextStyle(
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
    final hasContent = zone.content != ZoneContent.empty;
    final isSash =
        zone.content == ZoneContent.singleSash ||
        zone.content == ZoneContent.doubleSash;
    final structure = zone.glass.structure;

    Widget buildProcessingChip(
      String label,
      GlassProcessing type,
      bool isOuter,
      void Function(GlassProcessing) onTap,
    ) {
      final selected =
          (isOuter ? zone.glass.processingOuter : zone.glass.processingInner) ==
          type;
      return FilterChip(
        label: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            color: selected ? Colors.blue.shade900 : Colors.black87,
          ),
        ),
        selected: selected,
        selectedColor: Colors.blue.shade100,
        checkmarkColor: Colors.blue.shade900,
        onSelected: (_) => onTap(type),
      );
    }

    Widget buildGlassLayer(bool isOuter) {
      final finish = isOuter ? zone.glass.finishOuter : zone.glass.finishInner;
      final color = isOuter ? zone.glass.colorOuter : zone.glass.colorInner;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(top: 8, bottom: 4),
            child: Text(
              'نوع المعالجة:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          Wrap(
            spacing: 8,
            children: [
              buildProcessingChip(
                "عادي",
                GlassProcessing.none,
                isOuter,
                (t) => widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                ),
              ),
              buildProcessingChip(
                "مقسى",
                GlassProcessing.tempered,
                isOuter,
                (t) => widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                ),
              ),
              buildProcessingChip(
                "مورق",
                GlassProcessing.laminated,
                isOuter,
                (t) => widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                ),
              ),
              buildProcessingChip(
                "حراري",
                GlassProcessing.lowE,
                isOuter,
                (t) => widget.model.updateSelectedZoneGlass(
                  processingOuter: isOuter ? t : null,
                  processingInner: !isOuter ? t : null,
                ),
              ),
            ],
          ),
          const Padding(
            padding: EdgeInsets.only(top: 12, bottom: 4),
            child: Text(
              'المظهر:',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
            ),
          ),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
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
                          padding: const EdgeInsets.only(right: 8),
                          child: _ContentButton(
                            label: _getFinishName(f),
                            icon: Icons.blur_on_rounded,
                            selected: finish == f,
                            onPressed: () =>
                                widget.model.updateSelectedZoneGlass(
                                  finishOuter: isOuter ? f : null,
                                  finishInner: !isOuter ? f : null,
                                ),
                          ),
                        ),
                      )
                      .toList(),
            ),
          ),
          if (finish == GlassFinish.stopSol) ...[
            const Padding(
              padding: EdgeInsets.only(top: 12, bottom: 4),
              child: Text(
                'لون الزجاج (ستوبسول):',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
              ),
            ),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: GlassColor.values
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: _ContentButton(
                          label: _getColorName(c),
                          icon: Icons.palette_rounded,
                          selected: color == c,
                          onPressed: () => widget.model.updateSelectedZoneGlass(
                            colorOuter: isOuter ? c : null,
                            colorInner: !isOuter ? c : null,
                          ),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          ],
        ],
      );
    }

    // 🟢 1. يجب تعريف seriesName هنا أولاً لتجنب الخطأ
    String seriesName = widget.model.activeSeries != null
        ? widget.model.activeSeries!.name.toLowerCase()
        : '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.40,
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade300)),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'نوع المنطقة:',
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
                  // 🟢 نظام الفتح الفرنسي
                  if (widget.systemMode != 'sliding') ...[
                    _ContentButton(
                      label: 'فارغة',
                      icon: Icons.crop_free_rounded,
                      selected: zone.content == ZoneContent.empty,
                      onPressed: () => widget.model.setSelectedZoneContent(
                        ZoneContent.empty,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'زجاج ثابت',
                      icon: Icons.window_rounded,
                      selected: zone.content == ZoneContent.fixedGlass,
                      onPressed: () => widget.model.setSelectedZoneContent(
                        ZoneContent.fixedGlass,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'ضلفة واحدة',
                      icon: Icons.door_back_door_rounded,
                      selected: zone.content == ZoneContent.singleSash,
                      onPressed: () => widget.model.setSelectedZoneContent(
                        ZoneContent.singleSash,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'ضلفتان',
                      icon: Icons.garage_rounded,
                      selected: zone.content == ZoneContent.doubleSash,
                      onPressed: () => widget.model.setSelectedZoneContent(
                        ZoneContent.doubleSash,
                      ),
                    ),
                  ],

                  // 🟢 النظام المنزلق (Sliding)
                  if (widget.systemMode == 'sliding') ...[
                    _ContentButton(
                      label: 'زجاج ثابت',
                      icon: Icons.window_rounded,
                      selected: zone.content == ZoneContent.fixedGlass,
                      onPressed: () => widget.model.setSelectedZoneContent(
                        ZoneContent.fixedGlass,
                      ),
                    ),
                    const SizedBox(width: 8),
                    _ContentButton(
                      label: 'منزلق 2',
                      icon: Icons.sync_alt_rounded,
                      // التأكد من أن العدد هو 2 ليتلون الزر
                      selected:
                          zone.content == ZoneContent.slidingSash &&
                          zone.slidingSashesCount == 2,
                      onPressed: () {
                        widget.model.setSelectedZoneContent(
                          ZoneContent.slidingSash,
                        );
                        widget.model.setSlidingSashesCount(
                          2,
                        ); // 🟢 تحديد العدد 2
                      },
                    ),
                    // 🟢 أزرار إضافية تظهر فقط للسلاسل المخصصة (مثل 4 ضلفات)
                    // ضع هنا اسم السلسلة أو الكود الذي يدعم أكثر من 3 ضلفات
                    if (seriesName.contains('h36') ||
                        seriesName.contains('67000') ||
                        seriesName.contains('67000ld') ||
                        seriesName.contains('70kp')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 3',
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 3,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.slidingSash,
                          );
                          widget.model.setSlidingSashesCount(
                            3,
                          ); // تحديد العدد 4
                        },
                      ),
                    ],
                    if (seriesName.contains('h36')) ...[
                      const SizedBox(width: 8),
                      _ContentButton(
                        label: 'منزلق 4',
                        icon: Icons.sync_alt_rounded,
                        selected:
                            zone.content == ZoneContent.slidingSash &&
                            zone.slidingSashesCount == 4,
                        onPressed: () {
                          widget.model.setSelectedZoneContent(
                            ZoneContent.slidingSash,
                          );
                          widget.model.setSlidingSashesCount(
                            4,
                          ); // تحديد العدد 4
                        },
                      ),
                    ],
                  ],
                ],
              ),
            ),
            if (hasContent) ...[
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  'هيكل الزجاج:',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: GlassStructure.values
                      .map(
                        (s) => Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ContentButton(
                            label: _getStructureName(s),
                            icon: Icons.layers_rounded,
                            selected: structure == s,
                            onPressed: () => widget.model
                                .updateSelectedZoneGlass(structure: s),
                          ),
                        ),
                      )
                      .toList(),
                ),
              ),
              if (structure == GlassStructure.closed) ...[
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'المظهر (بانو):',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children:
                        [
                              GlassFinish.paneauSandwitch,
                              GlassFinish.resine,
                              GlassFinish.paneauSandwitchDecore,
                              GlassFinish.plexyGlass,
                              GlassFinish.bardage,
                            ]
                            .map(
                              (f) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ContentButton(
                                  label: _getFinishName(f),
                                  icon: Icons.blur_on_rounded,
                                  selected: zone.glass.finishInner == f,
                                  onPressed: () => widget.model
                                      .updateSelectedZoneGlass(finishInner: f),
                                ),
                              ),
                            )
                            .toList(),
                  ),
                ),
                const Padding(
                  padding: EdgeInsets.only(top: 12, bottom: 8),
                  child: Text(
                    'لون البانو:',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
                Builder(
                  builder: (context) {
                    List<ClosedGlassColor> allowedColors = [];
                    if (zone.glass.finishInner == GlassFinish.plexyGlass) {
                      allowedColors = [
                        ClosedGlassColor.transparent,
                        ClosedGlassColor.opaque,
                      ];
                    } else if (zone.glass.finishInner ==
                        GlassFinish.paneauSandwitch) {
                      allowedColors = [
                        ClosedGlassColor.white,
                        ClosedGlassColor.grissoris,
                        ClosedGlassColor.fbmClair,
                      ];
                    } else if (zone.glass.finishInner ==
                        GlassFinish.paneauSandwitchDecore) {
                      allowedColors = [
                        ClosedGlassColor.white,
                        ClosedGlassColor.grissoris,
                        ClosedGlassColor.fbmClair,
                      ];
                    } else if (zone.glass.finishInner == GlassFinish.bardage) {
                      allowedColors = [
                        ClosedGlassColor.white,
                        ClosedGlassColor.grissoris,
                        ClosedGlassColor.fbmClair,
                        ClosedGlassColor.fbmfonce,
                        ClosedGlassColor.grisClair,
                        ClosedGlassColor.black,
                        ClosedGlassColor.beige,
                      ];
                    } else if (zone.glass.finishInner == GlassFinish.resine) {
                      allowedColors = [
                        ClosedGlassColor.marberier,
                        ClosedGlassColor.white,
                        ClosedGlassColor.grissoris,
                        ClosedGlassColor.fbmClair,
                        ClosedGlassColor.fbmfonce,
                        ClosedGlassColor.grisClair,
                        ClosedGlassColor.black,
                        ClosedGlassColor.beige,
                      ];
                    }
                    return SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: allowedColors
                            .map(
                              (c) => Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: _ContentButton(
                                  label: _getClosedColoreName(c),
                                  icon: Icons.palette_rounded,
                                  selected: zone.glass.colorP == c,
                                  onPressed: () => widget.model
                                      .updateSelectedZoneGlass(colorP: c),
                                ),
                              ),
                            )
                            .toList(),
                      ),
                    );
                  },
                ),
              ] else if (structure == GlassStructure.double) ...[
                const SizedBox(height: 10),
                ExpansionTile(
                  title: const Text(
                    "الوجه الخارجي",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  children: [buildGlassLayer(true)],
                ),
                ExpansionTile(
                  title: const Text(
                    "الوجه الداخلي",
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: Colors.blue,
                    ),
                  ),
                  children: [buildGlassLayer(false)],
                ),
              ] else ...[
                const SizedBox(height: 10),
                buildGlassLayer(false),
              ],
            ],
            if (isSash) ...[
              const Padding(
                padding: EdgeInsets.only(top: 12, bottom: 8),
                child: Text(
                  'اتجاه الفتح وسمك الضلفة:',
                  style: TextStyle(
                    color: Colors.black87,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(
                  children: [
                    ...(zone.content == ZoneContent.doubleSash
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
                    const SizedBox(width: 10),
                    _ContentButton(
                      label: zone.isSash105
                          ? 'قطاع عريض (105)'
                          : 'قطاع عادي (104)',
                      icon: Icons.format_paint_rounded,
                      selected: zone.isSash105,
                      onPressed: () => widget.model.toggleSashType104105(),
                    ),
                    const SizedBox(width: 10),
                    _ContentButton(
                      label: widget.model.isFrame140
                          ? 'إطار عريض (140)'
                          : 'إطار عادي (103)',
                      icon: Icons.border_outer_rounded,
                      selected: widget.model.isFrame140,
                      onPressed: () => widget.model.toggleFrameType(),
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _getStructureName(GlassStructure s) {
    switch (s) {
      case GlassStructure.simple:
        return 'عادي';
      case GlassStructure.double:
        return 'مزدوج';
      case GlassStructure.closed:
        return 'بانو';
    }
  }

  String _getFinishName(GlassFinish f) {
    switch (f) {
      case GlassFinish.clair:
        return 'شفاف/عادي';
      case GlassFinish.stopSol:
        return 'ستوبسول';
      case GlassFinish.sable:
        return 'صابلي';
      case GlassFinish.delta:
        return 'دلتا';
      case GlassFinish.tuC:
        return 'تيسي';
      case GlassFinish.nevada:
        return 'نيفادا';
      case GlassFinish.cuisine:
        return 'مطبخ';
      case GlassFinish.aFleur:
        return 'مورد';
      case GlassFinish.paneauSandwitch:
        return 'بانو';
      case GlassFinish.resine:
        return 'ارزين';
      case GlassFinish.plexyGlass:
        return 'بليكسي قلاس';
      case GlassFinish.paneauSandwitchDecore:
        return 'بانو ديكور';
      case GlassFinish.bardage:
        return 'بارداش';
    }
  }

  String _getColorName(GlassColor c) {
    switch (c) {
      case GlassColor.transparent:
        return 'شفاف';
      case GlassColor.blue:
        return 'أزرق';
      case GlassColor.brown:
        return 'بني';
      case GlassColor.green:
        return 'أخضر';
      case GlassColor.gray:
        return 'رمادي';
      case GlassColor.grayAgc:
        return 'رمادي بلجيكي';
      case GlassColor.blueAgc:
        return 'ازرق بلجيكي';
    }
  }

  String _getClosedColoreName(ClosedGlassColor d) {
    switch (d) {
      case ClosedGlassColor.transparent:
        return 'شفاف';
      case ClosedGlassColor.white:
        return 'ابيض';
      case ClosedGlassColor.grisClair:
        return 'رمادي فاتح';
      case ClosedGlassColor.fbmfonce:
        return 'خشبي داكن';
      case ClosedGlassColor.grissoris:
        return 'رمادي داكن';
      case ClosedGlassColor.black:
        return 'اسود';
      case ClosedGlassColor.beige:
        return 'باج';
      case ClosedGlassColor.fbmClair:
        return 'خشبي فاتح';
      case ClosedGlassColor.opaque:
        return 'عاتم';
      case ClosedGlassColor.marberier:
        return 'رخامي';
    }
  }

  String _getDirectionName(OpenDirection d) {
    switch (d) {
      case OpenDirection.left:
        return 'يسار';
      case OpenDirection.right:
        return 'يمين';
      case OpenDirection.top:
        return 'أعلى';
      case OpenDirection.bottom:
        return 'أسفل';
    }
  }

  Widget _buildStatusBar(BuildContext context) {
    final zone = widget.model.selectedZone;
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    zone == null
                        ? 'انقر لتحديد وتعديل أي منطقة'
                        : 'المنطقة المحددة: ${zone.content.name}  |  الأبعاد: ${zone.boundary.width.toInt()} × ${zone.boundary.height.toInt()} mm',
                    style: const TextStyle(color: Colors.black54, fontSize: 12),
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
                              backgroundColor: Colors.blue,
                              padding: const EdgeInsets.symmetric(vertical: 10),
                            ),
                            onPressed: () {
                              _showCuttingListDialog(context);
                            },
                            child: const Text(
                              'حساب التقطيع',
                              style: TextStyle(
                                fontSize: 15,
                                color: Colors.white,
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
      ),
    );
  }
}

class _ToolButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool enabled;
  final Color color;
  final VoidCallback onPressed;

  const _ToolButton({
    required this.icon,
    required this.label,
    required this.enabled,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return ElevatedButton.icon(
      onPressed: enabled ? onPressed : null,
      icon: Icon(icon, size: 16, color: enabled ? Colors.white : Colors.grey),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          color: enabled ? Colors.white : Colors.grey,
        ),
      ),
      style: ElevatedButton.styleFrom(
        backgroundColor: enabled ? color : Colors.grey.shade200,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        elevation: 0,
      ),
    );
  }
}

class _ContentButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onPressed;

  const _ContentButton({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onPressed,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? Colors.blue.shade50 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: selected ? Colors.blue : Colors.grey.shade300,
            width: 1.5,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 16,
              color: selected ? Colors.blue : Colors.grey.shade600,
            ),
            const SizedBox(width: 5),
            Text(
              label,
              style: TextStyle(
                color: selected ? Colors.blue.shade900 : Colors.grey.shade800,
                fontSize: 12,
                fontWeight: selected ? FontWeight.bold : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppWorkspacePainter extends CustomPainter {
  final WindowModel model;

  AppWorkspacePainter({required this.model}) : super(repaint: model);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    // 🟢 1. تطبيق مقياس الزوم والتموضع التلقائي ليتناسب الإطار مع الشاشة
    canvas.translate(model.canvasDx, model.canvasDy);
    canvas.scale(model.canvasScale);

    // 🟢 2. رسم النافذة بالرسام الأصلي
    if (model.width > 0 && model.height > 0 && model.zones.isNotEmpty) {
      final painter = WindowPainter(model: model);
      painter.paint(canvas, size);

      // رسم الأبعاد الخارجية
      _paintDimensions(canvas, model, Offset.zero);
    }

    // 🟢 3. رسم المستطيل الأزرق التفاعلي أثناء سحب الإطار لأول مرة
    if (model.zones.isEmpty &&
        model.isDrawingMode &&
        model.drawingStart != null &&
        model.drawingCurrent != null) {
      final r = Rect.fromPoints(model.drawingStart!, model.drawingCurrent!);
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent.withValues(alpha: 0.2)
          ..style = PaintingStyle.fill,
      );
      canvas.drawRect(
        r,
        Paint()
          ..color = Colors.blueAccent
          ..style = PaintingStyle.stroke
          ..strokeWidth = 4.0 / model.canvasScale,
      );
    }

    canvas.restore();
  }

  void _paintDimensions(Canvas canvas, WindowModel model, Offset pos) {
    double offsetDistTop = 100.0;
    if (model.hasShutter) offsetDistTop += 150.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('top')) {
      offsetDistTop += 60.0;
    }

    double offsetDistLeft = 100.0;
    if (model.hasSideCovers && !model.removedShutterSides.contains('left')) {
      offsetDistLeft += 60.0;
    }

    Offset wMid = Offset(pos.dx + model.width / 2, pos.dy - offsetDistTop);
    _drawText(canvas, '${model.width.toInt()} mm', wMid, isVertical: false);
    _drawArrow(
      canvas,
      Offset(pos.dx, pos.dy - offsetDistTop),
      Offset(pos.dx + model.width, pos.dy - offsetDistTop),
      isVerticalLine: false,
    );

    Offset hMid = Offset(
      pos.dx - offsetDistLeft - 30.0,
      pos.dy + model.height / 2,
    );
    _drawText(canvas, '${model.height.toInt()} mm', hMid, isVertical: true);
    _drawArrow(
      canvas,
      Offset(pos.dx - offsetDistLeft, pos.dy),
      Offset(pos.dx - offsetDistLeft, pos.dy + model.height),
      isVerticalLine: true,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset center, {
    bool isVertical = false,
  }) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: const TextStyle(
          color: Colors.blue,
          fontWeight: FontWeight.bold,
          fontSize: 60,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    canvas.save();
    canvas.translate(center.dx, center.dy);
    if (isVertical) canvas.rotate(-math.pi / 2);
    final rect = Rect.fromCenter(
      center: Offset.zero,
      width: tp.width + 16,
      height: tp.height + 8,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(6)),
      Paint()..color = Colors.white.withValues(alpha: 0.95),
    );
    tp.paint(canvas, Offset(-tp.width / 2, -tp.height / 2));
    canvas.restore();
  }

  void _drawArrow(
    Canvas canvas,
    Offset p1,
    Offset p2, {
    bool isVerticalLine = false,
  }) {
    final p = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 4.0;
    canvas.drawLine(p1, p2, p);
    final Paint tickPaint = Paint()
      ..color = Colors.blueGrey
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    double tickSize = 15.0;

    if (isVerticalLine) {
      canvas.drawLine(
        Offset(p1.dx - tickSize, p1.dy),
        Offset(p1.dx + tickSize, p1.dy),
        tickPaint,
      );
      canvas.drawLine(
        Offset(p2.dx - tickSize, p2.dy),
        Offset(p2.dx + tickSize, p2.dy),
        tickPaint,
      );
    } else {
      canvas.drawLine(
        Offset(p1.dx, p1.dy - tickSize),
        Offset(p1.dx, p1.dy + tickSize),
        tickPaint,
      );
      canvas.drawLine(
        Offset(p2.dx, p2.dy - tickSize),
        Offset(p2.dx, p2.dy + tickSize),
        tickPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
