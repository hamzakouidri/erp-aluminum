import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';

class ResizableTableColumn {
  final String id;
  final Widget label;
  final Widget? filter;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final AlignmentGeometry alignment;

  const ResizableTableColumn({
    required this.id,
    required this.label,
    this.filter,
    required this.initialWidth,
    this.minWidth = 60,
    this.maxWidth = 700,
    this.alignment = AlignmentDirectional.centerStart,
  });
}

class ResizableTableRow {
  final List<Widget> cells;
  final Color? color;
  final VoidCallback? onTap;

  const ResizableTableRow({required this.cells, this.color, this.onTap});
}

class ResizableColumnsTable extends StatefulWidget {
  final List<ResizableTableColumn> columns;
  final List<ResizableTableRow> rows;
  final Color? headerColor;
  final Color? filterRowColor;
  final Color? borderColor;
  final Color? rowColor;
  final double headerMinHeight;
  final double filterRowMinHeight;
  final double rowMinHeight;
  final EdgeInsets cellPadding;
  final ScrollController? horizontalController;
  final ScrollController? verticalController;

  const ResizableColumnsTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headerColor,
    this.filterRowColor,
    this.borderColor,
    this.rowColor,
    this.headerMinHeight = 40,
    this.filterRowMinHeight = 38,
    this.rowMinHeight = 44,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
    this.horizontalController,
    this.verticalController,
  });

  @override
  State<ResizableColumnsTable> createState() => _ResizableColumnsTableState();
}

class _ResizableColumnsTableState extends State<ResizableColumnsTable> {
  final Map<String, double> _widths = {};
  String? _hoveredHandleColumnId;
  String? _draggingHandleColumnId;
  late final ScrollController _ownHorizontalController;

  ScrollController get _horizontalController =>
      widget.horizontalController ?? _ownHorizontalController;

  @override
  void initState() {
    super.initState();
    _ownHorizontalController = ScrollController();
  }

  @override
  void dispose() {
    if (widget.horizontalController == null) {
      _ownHorizontalController.dispose();
    }
    super.dispose();
  }

  double _widthFor(ResizableTableColumn column) =>
      _widths[column.id] ?? column.initialWidth;

  double get _tableWidth => widget.columns.fold<double>(
    0,
    (sum, column) => sum + _widthFor(column),
  );

  void _resize(ResizableTableColumn column, double delta) {
    final next = (_widthFor(column) + delta)
        .clamp(column.minWidth, column.maxWidth)
        .toDouble();
    setState(() => _widths[column.id] = next);
  }

  bool get _hasAnyFilter => widget.columns.any((c) => c.filter != null);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor =
        widget.borderColor ?? (isDark ? Colors.white12 : Colors.black12);
    final headerColor =
        widget.headerColor ??
        (isDark ? const Color(0xFF1E1E2C) : Colors.blueGrey.shade800);
    final filterRowColor =
        widget.filterRowColor ??
        (isDark ? const Color(0xFF1A1A26) : const Color(0xFFF1F5F9));
    final rowColor =
        widget.rowColor ?? (isDark ? const Color(0xFF171721) : Colors.white);

    return ScrollConfiguration(
      behavior: const MaterialScrollBehavior().copyWith(
        dragDevices: {
          PointerDeviceKind.touch,
          PointerDeviceKind.mouse,
          PointerDeviceKind.trackpad,
          PointerDeviceKind.stylus,
        },
      ),
      child: Scrollbar(
        controller: _horizontalController,
        thumbVisibility: true,
        interactive: true,
        child: SingleChildScrollView(
          controller: _horizontalController,
          scrollDirection: Axis.horizontal,
          child: SizedBox(
            width: _tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // 1. Header Row
                _buildHeader(headerColor, borderColor),

                // 2. Filter Sub-Row (under column headers)
                if (_hasAnyFilter)
                  _buildFilterRow(filterRowColor, borderColor),

                // 3. Table Rows inside vertical scrollable expanded or list
                ...widget.rows.map(
                  (row) => _buildRow(row, rowColor, borderColor),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(Color headerColor, Color borderColor) {
    return Container(
      color: headerColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.columns.length; i++)
              _buildHeaderCell(
                widget.columns[i],
                borderColor,
                isLast: i == widget.columns.length - 1,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    ResizableTableColumn column,
    Color borderColor, {
    required bool isLast,
  }) {
    final isHovered = _hoveredHandleColumnId == column.id;
    final isDragging = _draggingHandleColumnId == column.id;
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    return SizedBox(
      width: _widthFor(column),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Header Label Content (fills the entire cell width cleanly)
          Container(
            constraints: BoxConstraints(minHeight: widget.headerMinHeight),
            padding: widget.cellPadding,
            decoration: BoxDecoration(
              border: BorderDirectional(
                end: BorderSide(color: borderColor, width: 1.0),
              ),
            ),
            alignment: column.alignment,
            child: column.label,
          ),

          // Direct On-Divider Resize Handle (Overlay positioned right on the dividing line)
          if (!isLast)
            Positioned.directional(
              textDirection: isRtl ? TextDirection.rtl : TextDirection.ltr,
              end: -7,
              top: 0,
              bottom: 0,
              width: 14,
              child: MouseRegion(
                cursor: SystemMouseCursors.resizeColumn,
                onEnter: (_) => setState(() => _hoveredHandleColumnId = column.id),
                onExit: (_) => setState(() {
                  if (_draggingHandleColumnId != column.id) {
                    _hoveredHandleColumnId = null;
                  }
                }),
                child: GestureDetector(
                  behavior: HitTestBehavior.translucent,
                  onHorizontalDragStart: (_) =>
                      setState(() => _draggingHandleColumnId = column.id),
                  onHorizontalDragEnd: (_) => setState(() {
                    _draggingHandleColumnId = null;
                    _hoveredHandleColumnId = null;
                  }),
                  onHorizontalDragCancel: () => setState(() {
                    _draggingHandleColumnId = null;
                    _hoveredHandleColumnId = null;
                  }),
                  onHorizontalDragUpdate: (details) {
                    final delta = isRtl ? -details.delta.dx : details.delta.dx;
                    _resize(column, delta);
                  },
                  onDoubleTap: () =>
                      setState(() => _widths[column.id] = column.initialWidth),
                  child: Center(
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 150),
                      width: (isHovered || isDragging) ? 3.5 : 1.5,
                      height: double.infinity,
                      decoration: BoxDecoration(
                        color: (isHovered || isDragging)
                            ? const Color(0xFF38BDF8)
                            : Colors.white.withValues(alpha: 0.3),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildFilterRow(Color filterRowColor, Color borderColor) {
    return Container(
      color: filterRowColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.columns.length; i++)
              Container(
                width: _widthFor(widget.columns[i]),
                constraints: BoxConstraints(minHeight: widget.filterRowMinHeight),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    bottom: BorderSide(color: borderColor, width: 1.0),
                    end: BorderSide(color: borderColor, width: 1.0),
                  ),
                ),
                alignment: widget.columns[i].alignment,
                child: widget.columns[i].filter ?? const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ResizableTableRow row, Color rowColor, Color borderColor) {
    final content = Container(
      color: row.color ?? rowColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < widget.columns.length; i++)
              _buildCell(
                row.cells.length > i ? row.cells[i] : const SizedBox.shrink(),
                widget.columns[i],
                borderColor,
              ),
          ],
        ),
      ),
    );
    if (row.onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: row.onTap, child: content),
    );
  }

  Widget _buildCell(
    Widget child,
    ResizableTableColumn column,
    Color borderColor,
  ) {
    return Container(
      width: _widthFor(column),
      constraints: BoxConstraints(minHeight: widget.rowMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: BorderSide(color: borderColor, width: 1.0),
          end: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      alignment: column.alignment,
      child: child,
    );
  }
}
