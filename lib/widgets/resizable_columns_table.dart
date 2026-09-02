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
  final ValueChanged<Offset>? onSecondaryTapDown;
  final String? reorderId;

  const ResizableTableRow({
    required this.cells,
    this.color,
    this.onTap,
    this.onSecondaryTapDown,
    this.reorderId,
  });
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
  /// Gives an unbounded table a real viewport so the mouse wheel can scroll
  /// its rows instead of scrolling only the outer page.
  final double? maxBodyHeight;
  /// Enables long-press/mouse-drag reordering of rows for desktop tables.
  /// Reordering changes display order only; calculations remain unchanged.
  final bool reorderableRows;
  final ValueChanged<List<String>>? onRowOrderChanged;

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
    this.maxBodyHeight,
    this.reorderableRows = false,
    this.onRowOrderChanged,
  });

  @override
  State<ResizableColumnsTable> createState() => _ResizableColumnsTableState();
}

class _ResizableColumnsTableState extends State<ResizableColumnsTable> {
  final Map<String, double> _widths = {};
  String? _hoveredHandleColumnId;
  String? _draggingHandleColumnId;
  late final ScrollController _ownHorizontalController;
  late final ScrollController _ownVerticalController;
  List<String> _rowOrder = [];

  ScrollController get _horizontalController =>
      widget.horizontalController ?? _ownHorizontalController;

  ScrollController get _verticalController =>
      widget.verticalController ?? _ownVerticalController;

  @override
  void initState() {
    super.initState();
    _ownHorizontalController = ScrollController();
    _ownVerticalController = ScrollController();
    _syncRowOrder();
  }

  @override
  void didUpdateWidget(covariant ResizableColumnsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncRowOrder();
  }

  @override
  void dispose() {
    if (widget.horizontalController == null) {
      _ownHorizontalController.dispose();
    }
    if (widget.verticalController == null) {
      _ownVerticalController.dispose();
    }
    super.dispose();
  }

  double _widthFor(ResizableTableColumn column) =>
      _widths[column.id] ?? column.initialWidth;

  double get _tableWidth =>
      widget.columns.fold<double>(0, (sum, column) => sum + _widthFor(column));

  void _resize(ResizableTableColumn column, double delta) {
    final next = (_widthFor(column) + delta)
        .clamp(column.minWidth, column.maxWidth)
        .toDouble();
    setState(() => _widths[column.id] = next);
  }

  bool get _hasAnyFilter => widget.columns.any((c) => c.filter != null);

  String _rowId(ResizableTableRow row, int index) =>
      row.reorderId ?? '__row_index_$index';

  void _syncRowOrder() {
    if (!widget.reorderableRows) {
      _rowOrder = [];
      return;
    }
    final available = <String>[
      for (var i = 0; i < widget.rows.length; i++) _rowId(widget.rows[i], i),
    ];
    final availableSet = available.toSet();
    final previous = _rowOrder.toSet();
    _rowOrder = [
      ..._rowOrder.where(availableSet.contains),
      ...available.where((id) => !previous.contains(id)),
    ];
  }

  List<({String id, ResizableTableRow row})> _orderedRows() {
    if (!widget.reorderableRows) {
      return [
        for (var i = 0; i < widget.rows.length; i++)
          (id: _rowId(widget.rows[i], i), row: widget.rows[i]),
      ];
    }
    final byId = <String, ResizableTableRow>{
      for (var i = 0; i < widget.rows.length; i++)
        _rowId(widget.rows[i], i): widget.rows[i],
    };
    return [
      for (final id in _rowOrder)
        if (byId[id] != null) (id: id, row: byId[id]!),
    ];
  }

  void _reorderRows(int oldIndex, int newIndex) {
    final rows = _orderedRows();
    if (oldIndex < 0 || oldIndex >= rows.length) return;
    if (newIndex > oldIndex) newIndex -= 1;
    newIndex = newIndex.clamp(0, rows.length - 1);
    final next = rows.map((entry) => entry.id).toList();
    final moved = next.removeAt(oldIndex);
    next.insert(newIndex, moved);
    setState(() => _rowOrder = next);
    widget.onRowOrderChanged?.call(List<String>.unmodifiable(next));
  }

  Widget _buildReorderableRow(
    ({String id, ResizableTableRow row}) entry,
    int index,
    Color rowColor,
    Color borderColor,
  ) {
    return KeyedSubtree(
      key: ValueKey(entry.id),
      child: ReorderableDelayedDragStartListener(
        index: index,
        child: Stack(
          children: [
            _buildRow(entry.row, rowColor, borderColor),
            PositionedDirectional(
              top: 0,
              end: 3,
              bottom: 0,
              child: IgnorePointer(
                child: Center(
                  child: Icon(
                    Icons.drag_indicator_rounded,
                    size: 22,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.white38
                        : Colors.blueGrey.shade400,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

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

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBoundedHeight = constraints.maxHeight.isFinite;
        final bodyHeight = isBoundedHeight
            ? constraints.maxHeight
            : widget.maxBodyHeight;
        final bodyIsBounded = bodyHeight != null && bodyHeight.isFinite;

        final orderedRows = _orderedRows();
        Widget bodyContent = widget.reorderableRows
            ? ReorderableListView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                buildDefaultDragHandles: false,
                itemCount: orderedRows.length,
                onReorder: _reorderRows,
                proxyDecorator: (child, index, animation) => Material(
                  color: Colors.transparent,
                  elevation: 8,
                  child: child,
                ),
                itemBuilder: (context, index) => _buildReorderableRow(
                  orderedRows[index],
                  index,
                  rowColor,
                  borderColor,
                ),
              )
            : Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final entry in orderedRows)
                    _buildRow(entry.row, rowColor, borderColor),
                ],
              );

        Widget tableBody;
        if (bodyIsBounded) {
          tableBody = Expanded(
            child: SingleChildScrollView(
              controller: _verticalController,
              scrollDirection: Axis.vertical,
              physics: const AlwaysScrollableScrollPhysics(),
              child: bodyContent,
            ),
          );
        } else {
          tableBody = bodyContent;
        }

        final tableContent = SizedBox(
          width: _tableWidth,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: bodyIsBounded ? MainAxisSize.max : MainAxisSize.min,
            children: [
              // 1. Header Row
              _buildHeader(headerColor, borderColor),

              // 2. Filter Sub-Row (under column headers)
              if (_hasAnyFilter) _buildFilterRow(filterRowColor, borderColor),

              // 3. Table Rows
              tableBody,
            ],
          ),
        );

        return ScrollConfiguration(
          behavior: ScrollConfiguration.of(context).copyWith(
            dragDevices: {
              PointerDeviceKind.touch,
              PointerDeviceKind.mouse,
              PointerDeviceKind.trackpad,
              PointerDeviceKind.stylus,
            },
          ),
          child: SingleChildScrollView(
            controller: _horizontalController,
            scrollDirection: Axis.horizontal,
            child: bodyIsBounded
                ? SizedBox(
                    height: bodyHeight,
                    child: tableContent,
                  )
                : tableContent,
            ),
        );
      },
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
                onEnter: (_) =>
                    setState(() => _hoveredHandleColumnId = column.id),
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
                constraints: BoxConstraints(
                  minHeight: widget.filterRowMinHeight,
                ),
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
    if (row.onTap == null && row.onSecondaryTapDown == null) return content;
    return Material(
      color: Colors.transparent,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: row.onSecondaryTapDown == null
            ? null
            : (details) => row.onSecondaryTapDown!(details.globalPosition),
        child: InkWell(onTap: row.onTap, child: content),
      ),
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
