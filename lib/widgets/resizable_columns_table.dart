import 'dart:async';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  /// Enables long-press dragging of a header to move a column.
  final bool reorderableColumns;
  /// Stable identifier used to persist widths and column order for this table.
  final String? persistenceKey;
  final ValueChanged<List<String>>? onColumnOrderChanged;

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
    this.reorderableColumns = true,
    this.persistenceKey,
    this.onColumnOrderChanged,
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
  List<String> _columnOrder = [];
  int _preferencesLoadGeneration = 0;
  Future<void> _persistenceQueue = Future<void>.value();

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
    _syncColumnOrder();
    unawaited(_loadTablePreferences());
  }

  @override
  void didUpdateWidget(covariant ResizableColumnsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldNamespace = _storageNamespaceFor(
      oldWidget.columns,
      oldWidget.persistenceKey,
    );
    final namespaceChanged = oldNamespace != _storageNamespace;
    final columnsChanged = !_sameColumnIds(
      oldWidget.columns,
      widget.columns,
    );
    if (namespaceChanged) {
      _widths.clear();
      _columnOrder = [];
    }
    _syncRowOrder();
    _syncColumnOrder();
    if (namespaceChanged || columnsChanged) {
      unawaited(_loadTablePreferences());
    }
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

  String _storageNamespaceFor(
    List<ResizableTableColumn> columns,
    String? persistenceKey,
  ) {
    final explicit = persistenceKey?.trim();
    if (explicit != null && explicit.isNotEmpty) return explicit;
    return columns.map((column) => column.id).join('__');
  }

  String get _storageNamespace =>
      _storageNamespaceFor(widget.columns, widget.persistenceKey);

  bool _sameColumnIds(
    List<ResizableTableColumn> first,
    List<ResizableTableColumn> second,
  ) {
    if (first.length != second.length) return false;
    for (var i = 0; i < first.length; i++) {
      if (first[i].id != second[i].id) return false;
    }
    return true;
  }

  String get _widthStoragePrefix =>
      'resizable_table_widths_${_storageNamespace}_';

  String get _orderStorageKey =>
      'resizable_table_column_order_$_storageNamespace';

  Future<void> _loadTablePreferences() async {
    final loadGeneration = ++_preferencesLoadGeneration;
    final namespace = _storageNamespace;
    final columns = List<ResizableTableColumn>.from(widget.columns);
    try {
      final prefs = await SharedPreferences.getInstance();
      final availableIds = columns.map((column) => column.id).toSet();
      final orderStorageKey =
          'resizable_table_column_order_$namespace';
      final widthStoragePrefix = 'resizable_table_widths_${namespace}_';
      final savedOrder = prefs.getStringList(orderStorageKey) ?? const [];
      final savedWidths = <String, double>{};
      for (final column in columns) {
        final savedWidth =
            prefs.getDouble('$widthStoragePrefix${column.id}');
        if (savedWidth != null) savedWidths[column.id] = savedWidth;
      }
      if (!mounted ||
          loadGeneration != _preferencesLoadGeneration ||
          namespace != _storageNamespace ||
          !_sameColumnIds(columns, widget.columns)) {
        return;
      }
      setState(() {
        _widths.addAll(savedWidths);
        _columnOrder = [
          ...savedOrder.where(availableIds.contains),
          ...columns
              .map((column) => column.id)
              .where((id) => !savedOrder.contains(id)),
        ];
      });
    } catch (_) {
      // Layout preferences are optional; the table still uses its defaults.
    }
  }

  void _persistWidth(String columnId, double width) {
    _enqueuePersistence(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setDouble('$_widthStoragePrefix$columnId', width);
      } catch (_) {
        // Persistence is best-effort; the current table state remains live.
      }
    });
  }

  void _persistColumnOrder() {
    final order = List<String>.from(_columnOrder);
    _enqueuePersistence(() async {
      try {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setStringList(_orderStorageKey, order);
      } catch (_) {
        // Persistence is best-effort; the current table state remains live.
      }
    });
  }

  void _enqueuePersistence(Future<void> Function() operation) {
    _persistenceQueue = _persistenceQueue.then((_) async {
      try {
        await operation();
      } catch (_) {
        // Layout persistence is best-effort; the current table state remains.
      }
    });
  }

  List<ResizableTableColumn> _orderedColumns() {
    final byId = <String, ResizableTableColumn>{
      for (final column in widget.columns) column.id: column,
    };
    return [
      for (final id in _columnOrder)
        if (byId[id] != null) byId[id]!,
      for (final column in widget.columns)
        if (!_columnOrder.contains(column.id)) column,
    ];
  }

  void _syncColumnOrder() {
    final available = widget.columns.map((column) => column.id).toList();
    final availableSet = available.toSet();
    final previous = _columnOrder.toSet();
    _columnOrder = [
      ..._columnOrder.where(availableSet.contains),
      ...available.where((id) => !previous.contains(id)),
    ];
  }

  double get _tableWidth =>
      widget.columns.fold<double>(0, (sum, column) => sum + _widthFor(column));

  void _resize(ResizableTableColumn column, double delta) {
    final next = (_widthFor(column) + delta)
        .clamp(column.minWidth, column.maxWidth)
        .toDouble();
    _preferencesLoadGeneration++;
    setState(() => _widths[column.id] = next);
    _persistWidth(column.id, next);
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

  void _reorderColumns(String draggedId, String targetId) {
    if (!widget.reorderableColumns || draggedId == targetId) return;
    final next = List<String>.from(_columnOrder);
    final oldIndex = next.indexOf(draggedId);
    var targetIndex = next.indexOf(targetId);
    if (oldIndex < 0 || targetIndex < 0) return;
    next.removeAt(oldIndex);
    if (oldIndex < targetIndex) targetIndex -= 1;
    next.insert(targetIndex, draggedId);
    _preferencesLoadGeneration++;
    setState(() => _columnOrder = next);
    _persistColumnOrder();
    widget.onColumnOrderChanged?.call(List<String>.unmodifiable(next));
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
    final columns = _orderedColumns();
    return Container(
      color: headerColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++)
              _buildHeaderCell(
                columns[i],
                borderColor,
                isLast: i == columns.length - 1,
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

    final headerLabel = Container(
      constraints: BoxConstraints(minHeight: widget.headerMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: BorderDirectional(
          end: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      alignment: column.alignment,
      child: column.label,
    );
    final draggableLabel = widget.reorderableColumns
        ? LongPressDraggable<String>(
            data: column.id,
            delay: const Duration(milliseconds: 250),
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: _widthFor(column),
                constraints: BoxConstraints(
                  minHeight: widget.headerMinHeight,
                ),
                padding: widget.cellPadding,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? const Color(0xFF334155)
                      : Colors.blueGrey.shade700,
                  borderRadius: BorderRadius.circular(6),
                ),
                child: column.label,
              ),
            ),
            childWhenDragging: Opacity(opacity: 0.35, child: headerLabel),
            child: headerLabel,
          )
        : headerLabel;

    final baseHeaderContent = Stack(
      clipBehavior: Clip.none,
      children: [
        draggableLabel,
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
                onDoubleTap: () {
                  _preferencesLoadGeneration++;
                  setState(() => _widths[column.id] = column.initialWidth);
                  _persistWidth(column.id, column.initialWidth);
                },
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
    );

    Widget headerContent = baseHeaderContent;
    if (widget.reorderableColumns) {
      headerContent = DragTarget<String>(
        onWillAcceptWithDetails: (details) => details.data != column.id,
        onAcceptWithDetails: (details) =>
            _reorderColumns(details.data, column.id),
        builder: (context, candidateData, rejectedData) {
          final isDropTarget = candidateData.isNotEmpty;
          return DecoratedBox(
            decoration: isDropTarget
                ? BoxDecoration(
                    border: Border.all(
                      color: const Color(0xFF38BDF8),
                      width: 2,
                    ),
                  )
                : const BoxDecoration(),
            child: baseHeaderContent,
          );
        },
      );
    }

    return SizedBox(
      width: _widthFor(column),
      child: headerContent,
    );
    /*
      Legacy header implementation retained below in source history was
      replaced by the draggable header above.
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
    );*/
  }

  Widget _buildFilterRow(Color filterRowColor, Color borderColor) {
    final columns = _orderedColumns();
    return Container(
      color: filterRowColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < columns.length; i++)
              Container(
                width: _widthFor(columns[i]),
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
                alignment: columns[i].alignment,
                child: columns[i].filter ?? const SizedBox.shrink(),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildRow(ResizableTableRow row, Color rowColor, Color borderColor) {
    final columns = _orderedColumns();
    final originalIndexById = <String, int>{
      for (var i = 0; i < widget.columns.length; i++) widget.columns[i].id: i,
    };
    final content = Container(
      color: row.color ?? rowColor,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final column in columns)
              _buildCell(
                row.cells.length > (originalIndexById[column.id] ?? -1)
                    ? row.cells[originalIndexById[column.id]!]
                    : const SizedBox.shrink(),
                column,
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
