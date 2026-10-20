import 'dart:async';
import 'dart:convert';
import 'dart:ui' show PointerDeviceKind;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'
    show KeyDownEvent, KeyEvent, KeyRepeatEvent, LogicalKeyboardKey;
import 'package:shared_preferences/shared_preferences.dart';
import 'desktop_scroll_behavior.dart';
import 'context_menu_gate.dart';

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
  final VoidCallback? onDoubleTap;
  final KeyEventResult Function(KeyEvent)? onKeyEvent;
  final ValueChanged<Offset>? onSecondaryTapDown;
  final String? reorderId;

  const ResizableTableRow({
    required this.cells,
    this.color,
    this.onTap,
    this.onDoubleTap,
    this.onKeyEvent,
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

  /// Fixed summary cells keyed by column ID; never part of row scrolling.
  final Map<String, Widget>? footerCells;
  final ValueChanged<List<String>>? onRowOrderChanged;

  /// Enables long-press dragging of a header to move a column.
  final bool reorderableColumns;

  /// Stable identifier used to persist widths and column order for this table.
  final String? persistenceKey;
  final ValueChanged<List<String>>? onColumnOrderChanged;

  /// Color used to highlight the row currently focused via keyboard
  /// navigation (arrow keys / Home / End) or a row click. Defaults to the
  /// theme's primary color blended over the row's own background.
  final Color? focusedRowColor;

  /// Called whenever the focused/highlighted row changes, with the row's
  /// [ResizableTableRow.reorderId] (or its display index if none was given).
  /// Null means no row is currently focused.
  final ValueChanged<String?>? onFocusedRowChanged;
  final String? revealRowId;

  /// Optional widget displayed in the table body when [rows] is empty,
  /// while keeping the table header and filter search rows visible.
  final Widget? emptyPlaceholder;

  /// Adds a fixed visual sequence column at the far left of the table.
  /// The number follows the current displayed order after filtering, sorting
  /// and row reordering; it is deliberately excluded from persisted layout.
  final bool showRowNumbers;

  const ResizableColumnsTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headerColor,
    this.filterRowColor,
    this.borderColor,
    this.rowColor,
    this.headerMinHeight = 46,
    this.filterRowMinHeight = 42,
    this.rowMinHeight = 48,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
    this.horizontalController,
    this.verticalController,
    this.maxBodyHeight,
    this.reorderableRows = false,
    this.footerCells,
    this.onRowOrderChanged,
    this.reorderableColumns = true,
    this.persistenceKey,
    this.onColumnOrderChanged,
    this.focusedRowColor,
    this.onFocusedRowChanged,
    this.revealRowId,
    this.emptyPlaceholder,
    this.showRowNumbers = true,
  });

  /// The shared visual language used by every interactive table in the app.
  /// Keeping these colors here prevents individual screens from drifting into
  /// unrelated table designs.
  static const lightHeaderColor = Color(0xFFE7EEFC);
  static const lightFilterColor = Color(0xFFF5F8FE);
  static const lightRowColor = Color(0xFFFFFFFF);
  static const lightBorderColor = Color(0xFFE5EAF3);
  static const darkHeaderColor = Color(0xFF25324A);
  static const darkFilterColor = Color(0xFF1E293B);
  static const darkRowColor = Color(0xFF171B24);
  static const darkBorderColor = Color(0xFF303B50);

  @override
  State<ResizableColumnsTable> createState() => _ResizableColumnsTableState();
}

class _ResizableColumnsTableState extends State<ResizableColumnsTable> {
  static const double _rowNumberWidth = 58.0;
  final Map<String, double> _widths = {};
  String? _hoveredHandleColumnId;
  String? _draggingHandleColumnId;
  late final ScrollController _ownHorizontalController;
  late final ScrollController _ownVerticalController;
  late final FocusNode _tableFocusNode;
  List<String> _rowOrder = [];
  List<String> _columnOrder = [];
  final Set<String> _hiddenColumnIds = <String>{};
  int _preferencesLoadGeneration = 0;
  Future<void> _persistenceQueue = Future<void>.value();
  Future<SharedPreferences>? _preferencesFuture;

  /// Index (within the currently displayed row order) of the row highlighted
  /// via keyboard navigation or a row click. Null means no row is focused.
  int? _focusedRowIndex;
  String? _hoveredRowId;

  /// Stable per-row keys (keyed by row id) used to scroll a row into view
  /// with [Scrollable.ensureVisible] regardless of its actual rendered
  /// height.
  final Map<String, GlobalKey> _rowKeysById = {};

  ScrollController get _horizontalController =>
      widget.horizontalController ?? _ownHorizontalController;

  ScrollController get _verticalController =>
      widget.verticalController ?? _ownVerticalController;

  @override
  void initState() {
    super.initState();
    _ownHorizontalController = ScrollController();
    _ownVerticalController = ScrollController();
    _tableFocusNode = FocusNode(debugLabel: 'ResizableColumnsTable');
    _syncRowOrder();
    _syncColumnOrder();
    unawaited(_loadTablePreferences());
    _revealRequestedRow();
  }

  @override
  void didUpdateWidget(covariant ResizableColumnsTable oldWidget) {
    super.didUpdateWidget(oldWidget);
    final oldNamespace = _storageNamespaceFor(
      oldWidget.columns,
      oldWidget.persistenceKey,
    );
    final namespaceChanged = oldNamespace != _storageNamespace;
    final columnsChanged = !_sameColumnIds(oldWidget.columns, widget.columns);
    if (namespaceChanged) {
      _widths.clear();
      _columnOrder = [];
      _hiddenColumnIds.clear();
    }
    _syncRowOrder();
    _syncColumnOrder();
    // The row set can shrink (filtering, deletion, etc.) between rebuilds;
    // keep the focused index inside the valid range instead of pointing at a
    // row that no longer exists.
    if (_focusedRowIndex != null && _focusedRowIndex! >= widget.rows.length) {
      _focusedRowIndex = widget.rows.isEmpty ? null : widget.rows.length - 1;
    }
    if (namespaceChanged || columnsChanged) {
      unawaited(_loadTablePreferences());
    }
    if (widget.revealRowId != oldWidget.revealRowId ||
        widget.rows.length != oldWidget.rows.length) {
      _revealRequestedRow();
    }
  }

  void _revealRequestedRow() {
    final targetId = widget.revealRowId;
    if (targetId == null || targetId.isEmpty) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final key = _rowKeysById[targetId];
      final rowContext = key?.currentContext;
      if (rowContext == null) return;
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.35,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOutCubic,
      );
    });
  }

  @override
  void dispose() {
    if (widget.horizontalController == null) {
      _ownHorizontalController.dispose();
    }
    if (widget.verticalController == null) {
      _ownVerticalController.dispose();
    }
    _tableFocusNode.dispose();
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

  Future<SharedPreferences> _getPreferences() =>
      _preferencesFuture ??= SharedPreferences.getInstance();

  Future<void> _loadTablePreferences() async {
    final loadGeneration = ++_preferencesLoadGeneration;
    final namespace = _storageNamespace;
    final columns = List<ResizableTableColumn>.from(widget.columns);
    try {
      final prefs = await _getPreferences();
      final availableIds = columns.map((column) => column.id).toSet();
      final orderStorageKey = 'resizable_table_column_order_$namespace';
      final widthStoragePrefix = 'resizable_table_widths_${namespace}_';
      final savedWidths = <String, double>{};
      var savedOrder = <String>[];
      final savedHidden = <String>{};
      final savedLayout = prefs.getString('resizable_table_layout_$namespace');
      if (savedLayout != null && savedLayout.trim().isNotEmpty) {
        try {
          final decoded = jsonDecode(savedLayout);
          if (decoded is Map) {
            final rawWidths = decoded['widths'];
            if (rawWidths is Map) {
              for (final entry in rawWidths.entries) {
                final raw = entry.value;
                final width = raw is num
                    ? raw.toDouble()
                    : double.tryParse(raw?.toString() ?? '');
                if (width != null) savedWidths[entry.key.toString()] = width;
              }
            }
            final rawOrder = decoded['order'];
            if (rawOrder is List) {
              savedOrder = rawOrder.map((id) => id.toString()).toList();
            }
            final rawHidden = decoded['hidden'];
            if (rawHidden is List) {
              savedHidden.addAll(
                rawHidden
                    .map((id) => id.toString())
                    .where(availableIds.contains),
              );
            }
          }
        } catch (_) {
          // Fall back to the legacy keys below.
        }
      }
      if (savedWidths.isEmpty) {
        for (final column in columns) {
          final savedWidth = prefs.getDouble('$widthStoragePrefix${column.id}');
          if (savedWidth != null) savedWidths[column.id] = savedWidth;
        }
      }
      if (savedOrder.isEmpty) {
        savedOrder = prefs.getStringList(orderStorageKey) ?? <String>[];
      }
      if (!mounted ||
          loadGeneration != _preferencesLoadGeneration ||
          namespace != _storageNamespace ||
          !_sameColumnIds(columns, widget.columns)) {
        return;
      }
      setState(() {
        _widths.addAll(savedWidths);
        _hiddenColumnIds
          ..clear()
          ..addAll(savedHidden);
        if (_hiddenColumnIds.length >= availableIds.length) {
          _hiddenColumnIds.remove(columns.first.id);
        }
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
    _persistLayout();
  }

  void _persistColumnOrder() {
    _persistLayout();
  }

  void _persistLayout() {
    final namespace = _storageNamespace;
    final layoutKey = 'resizable_table_layout_$namespace';
    final widths = <String, double>{..._widths};
    final order = List<String>.from(_columnOrder);
    final hidden = _hiddenColumnIds.toList(growable: false);
    _enqueuePersistence(() async {
      try {
        final prefs = await _getPreferences();
        await prefs.setString(
          layoutKey,
          jsonEncode(<String, dynamic>{
            'widths': widths,
            'order': order,
            'hidden': hidden,
          }),
        );
      } catch (_) {
        // Persistence is optional; the current table state remains live.
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

  List<ResizableTableColumn> _orderedColumns({bool includeHidden = false}) {
    final byId = <String, ResizableTableColumn>{
      for (final column in widget.columns) column.id: column,
    };
    final ordered = [
      for (final id in _columnOrder)
        if (byId[id] != null) byId[id]!,
      for (final column in widget.columns)
        if (!_columnOrder.contains(column.id)) column,
    ];
    if (includeHidden) return ordered;
    return ordered
        .where((column) => !_hiddenColumnIds.contains(column.id))
        .toList(growable: false);
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
      _orderedColumns().fold<double>(
        0,
        (sum, column) => sum + _widthFor(column),
      ) +
      (widget.showRowNumbers ? _rowNumberWidth : 0.0);

  void _toggleColumnVisibility(String columnId) {
    final isHidden = _hiddenColumnIds.contains(columnId);
    if (!isHidden && _orderedColumns().length <= 1) return;
    _preferencesLoadGeneration++;
    setState(() {
      if (isHidden) {
        _hiddenColumnIds.remove(columnId);
      } else {
        _hiddenColumnIds.add(columnId);
      }
    });
    _persistLayout();
  }

  Future<void> _showColumnVisibilityMenu(Offset globalPosition) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    // The list stays open while columns are shown or hidden; a click outside
    // it (or Esc) closes it.
    await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        Rect.fromPoints(globalPosition, globalPosition),
        Offset.zero & overlay.size,
      ),
      items: [
        for (final column in _orderedColumns(includeHidden: true))
          _ColumnToggleMenuEntry(
            label: column.label,
            isVisible: () => !_hiddenColumnIds.contains(column.id),
            // The last visible column cannot be hidden.
            canToggle: () =>
                _hiddenColumnIds.contains(column.id) ||
                _orderedColumns().length > 1,
            onToggle: () {
              if (mounted) _toggleColumnVisibility(column.id);
            },
          ),
      ],
    );
  }

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

  /// Returns the (and lazily creates a) stable [GlobalKey] for a given row id,
  /// so [Scrollable.ensureVisible] can locate that row's real, current
  /// on-screen position regardless of its rendered height.
  GlobalKey _rowKeyFor(String rowId) =>
      _rowKeysById.putIfAbsent(rowId, () => GlobalKey());

  /// Drops cached keys for rows that are no longer displayed, so the map
  /// doesn't grow unbounded as rows are filtered or removed over time.
  void _pruneRowKeys(Set<String> validRowIds) {
    _rowKeysById.removeWhere((id, _) => !validRowIds.contains(id));
  }

  /// Marks [index] as the focused/highlighted row (e.g. after a click) and
  /// moves keyboard focus onto the table so arrow-key navigation continues
  /// from that row.
  void _focusRow(int index) {
    if (_focusedRowIndex != index) {
      setState(() => _focusedRowIndex = index);
      widget.onFocusedRowChanged?.call(_rowIdAt(index));
    }
    _tableFocusNode.requestFocus();
  }

  String? _rowIdAt(int index) {
    final rows = _orderedRows();
    if (index < 0 || index >= rows.length) return null;
    return rows[index].id;
  }

  /// Scrolls (any ancestor Scrollable, including the table's own vertical
  /// viewport) so the row with [rowId] becomes visible. Deferred to the next
  /// frame so the row's key already has a laid-out context to look up.
  void _ensureRowVisible(String rowId) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final rowContext = _rowKeysById[rowId]?.currentContext;
      if (rowContext == null) return;
      Scrollable.ensureVisible(
        rowContext,
        alignment: 0.5,
        duration: const Duration(milliseconds: 120),
        curve: Curves.easeOut,
      );
    });
  }

  /// Moves the focused-row highlight with ArrowUp/ArrowDown/Home/End.
  ///
  /// This fully consumes those keys while the table (or a descendant, such as
  /// a row's InkWell) holds focus, so row navigation doesn't also trigger a
  /// competing page-level scroll for the same key press.
  KeyEventResult _handleTableKeyEvent(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    final rows = _orderedRows();
    if (rows.isEmpty) return KeyEventResult.ignored;

    final current = _focusedRowIndex ?? -1;
    if (current >= 0 && current < rows.length) {
      final result = rows[current].row.onKeyEvent?.call(event);
      if (result != null && result != KeyEventResult.ignored) return result;
    }
    int nextIndex;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.arrowDown:
        nextIndex = (current + 1).clamp(0, rows.length - 1);
        break;
      case LogicalKeyboardKey.arrowUp:
        nextIndex = (current - 1).clamp(0, rows.length - 1);
        break;
      case LogicalKeyboardKey.home:
        nextIndex = 0;
        break;
      case LogicalKeyboardKey.end:
        nextIndex = rows.length - 1;
        break;
      case LogicalKeyboardKey.arrowLeft:
      case LogicalKeyboardKey.arrowRight:
        // Left/right still belong to the horizontal viewport, but ensure a
        // visible active row exists while the user navigates the table.
        if (_focusedRowIndex == null) {
          setState(() => _focusedRowIndex = 0);
          widget.onFocusedRowChanged?.call(rows.first.id);
          _ensureRowVisible(rows.first.id);
        }
        return KeyEventResult.ignored;
      default:
        return KeyEventResult.ignored;
    }

    if (nextIndex != current) {
      setState(() => _focusedRowIndex = nextIndex);
      widget.onFocusedRowChanged?.call(rows[nextIndex].id);
      _ensureRowVisible(rows[nextIndex].id);
    }
    // Handled even when already at the first/last row, so the key press
    // doesn't fall through to a page-level scroll while a row is focused.
    return KeyEventResult.handled;
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
            _buildRow(entry.id, index, entry.row, rowColor, borderColor),
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
    final ambientTextDirection = Directionality.of(context);
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    // Deliberately use one palette everywhere. The legacy color arguments are
    // kept for source compatibility, but table styling is now centralized.
    final borderColor = isDark
        ? ResizableColumnsTable.darkBorderColor
        : ResizableColumnsTable.lightBorderColor;
    final headerColor = isDark
        ? ResizableColumnsTable.darkHeaderColor
        : ResizableColumnsTable.lightHeaderColor;
    final filterRowColor = isDark
        ? ResizableColumnsTable.darkFilterColor
        : ResizableColumnsTable.lightFilterColor;
    final rowColor = isDark
        ? ResizableColumnsTable.darkRowColor
        : ResizableColumnsTable.lightRowColor;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isBoundedHeight = constraints.maxHeight.isFinite;
        final bodyHeight = isBoundedHeight
            ? constraints.maxHeight
            : widget.maxBodyHeight;
        final bodyIsBounded = bodyHeight != null && bodyHeight.isFinite;

        final orderedRows = _orderedRows();
        _pruneRowKeys(orderedRows.map((entry) => entry.id).toSet());

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
                  for (var i = 0; i < orderedRows.length; i++)
                    _buildRow(
                      orderedRows[i].id,
                      i,
                      orderedRows[i].row,
                      rowColor,
                      borderColor,
                    ),
                ],
              );

        Widget tableBody;
        if (orderedRows.isEmpty && widget.emptyPlaceholder != null) {
          final placeholder = SizedBox(
            width: _tableWidth,
            child: widget.emptyPlaceholder!,
          );
          tableBody = bodyIsBounded
              ? Expanded(child: placeholder)
              : placeholder;
        } else if (bodyIsBounded) {
          tableBody = Expanded(
            child: SingleChildScrollView(
              controller: _verticalController,
              scrollDirection: Axis.vertical,
              primary: false,
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
              if (widget.footerCells != null)
                Container(
                  color: filterRowColor,
                  child: IntrinsicHeight(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (widget.showRowNumbers &&
                            Directionality.of(context) == TextDirection.ltr)
                          _buildNumberCell(
                            const SizedBox.shrink(),
                            borderColor,
                          ),
                        for (final column in _orderedColumns())
                          _buildCell(
                            widget.footerCells![column.id] ??
                                const SizedBox.shrink(),
                            column,
                            borderColor,
                          ),
                        if (widget.showRowNumbers &&
                            Directionality.of(context) == TextDirection.rtl)
                          _buildNumberCell(
                            const SizedBox.shrink(),
                            borderColor,
                          ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );

        // Keep the table geometry aligned with the active language. In RTL,
        // resize handles live on the left edge and dragging left enlarges the
        // column towards the pointer, instead of growing on the opposite side.
        return Directionality(
          textDirection: ambientTextDirection,
          child: MouseRegion(
            onEnter: (_) {
              if (!_tableFocusNode.hasFocus) _tableFocusNode.requestFocus();
            },
            child: Focus(
              focusNode: _tableFocusNode,
              onKeyEvent: _handleTableKeyEvent,
              child: ScrollConfiguration(
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
                  primary: false,
                  child: bodyIsBounded
                      ? SizedBox(
                          height: bodyHeight,
                          child: DesktopScrollFallback(
                            controller: _verticalController,
                            child: tableContent,
                          ),
                        )
                      : tableContent,
                ),
              ),
            ),
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
            if (widget.showRowNumbers &&
                Directionality.of(context) == TextDirection.ltr)
              _buildNumberHeaderCell(borderColor),
            for (var i = 0; i < columns.length; i++)
              _buildHeaderCell(
                columns[i],
                borderColor,
                isLast:
                    i == columns.length - 1 &&
                    (!widget.showRowNumbers ||
                        Directionality.of(context) == TextDirection.ltr),
              ),
            if (widget.showRowNumbers &&
                Directionality.of(context) == TextDirection.rtl)
              _buildNumberHeaderCell(borderColor),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberHeaderCell(Color borderColor) {
    return Container(
      width: _rowNumberWidth,
      constraints: BoxConstraints(minHeight: widget.headerMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      alignment: Alignment.center,
      child: const Text(
        'N°',
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
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
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      alignment: column.alignment,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13.5,
          fontWeight: FontWeight.w700,
        ),
        child: column.label,
      ),
    );
    final draggableLabel = widget.reorderableColumns
        ? LongPressDraggable<String>(
            data: column.id,
            delay: const Duration(milliseconds: 250),
            feedback: Material(
              color: Colors.transparent,
              child: Container(
                width: _widthFor(column),
                constraints: BoxConstraints(minHeight: widget.headerMinHeight),
                padding: widget.cellPadding,
                decoration: BoxDecoration(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? ResizableColumnsTable.darkHeaderColor
                      : ResizableColumnsTable.lightHeaderColor,
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
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onSecondaryTapDown: (details) => ContextMenuGate.run(
            () => _showColumnVisibilityMenu(details.globalPosition),
          ),
          child: draggableLabel,
        ),
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
                          : (Theme.of(context).brightness == Brightness.dark
                                ? Colors.white24
                                : const Color(0xFFB9C7E5)),
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
      key: ValueKey('header_col_' + column.id),
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
            if (widget.showRowNumbers &&
                Directionality.of(context) == TextDirection.ltr)
              _buildNumberFilterCell(borderColor),
            for (var i = 0; i < columns.length; i++)
              Container(
                key: ValueKey('filter_col_' + columns[i].id),
                width: _widthFor(columns[i]),
                constraints: BoxConstraints(
                  minHeight: widget.filterRowMinHeight,
                ),
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 3),
                decoration: BoxDecoration(
                  border: BorderDirectional(
                    bottom: BorderSide(color: borderColor, width: 1.0),
                  ),
                ),
                alignment: columns[i].alignment,
                child: columns[i].filter != null
                    ? KeyedSubtree(
                        key: ValueKey('filter_child_' + columns[i].id),
                        child: ClipRect(child: columns[i].filter!),
                      )
                    : const SizedBox.shrink(),
              ),
            if (widget.showRowNumbers &&
                Directionality.of(context) == TextDirection.rtl)
              _buildNumberFilterCell(borderColor),
          ],
        ),
      ),
    );
  }

  Widget _buildNumberFilterCell(Color borderColor) {
    return Container(
      width: _rowNumberWidth,
      constraints: BoxConstraints(minHeight: widget.filterRowMinHeight),
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
    );
  }

  Widget _buildRow(
    String rowId,
    int index,
    ResizableTableRow row,
    Color rowColor,
    Color borderColor,
  ) {
    final columns = _orderedColumns();
    final originalIndexById = <String, int>{
      for (var i = 0; i < widget.columns.length; i++) widget.columns[i].id: i,
    };

    final isFocused = _focusedRowIndex == index;
    final isHovered = _hoveredRowId == rowId;
    final theme = Theme.of(context);
    final accentColor = widget.focusedRowColor ?? theme.colorScheme.primary;
    final stripedRowColor = index.isOdd
        ? Color.alphaBlend(
            (theme.brightness == Brightness.dark ? Colors.white : Colors.blue)
                .withValues(alpha: 0.025),
            rowColor,
          )
        : rowColor;
    final baseColor = row.color ?? stripedRowColor;
    final effectiveColor = isFocused
        ? Color.alphaBlend(accentColor.withValues(alpha: 0.16), baseColor)
        : isHovered
        ? Color.alphaBlend(accentColor.withValues(alpha: 0.08), baseColor)
        : baseColor;

    final rowBody = Stack(
      children: [
        AnimatedContainer(
          key: ValueKey('table_row_surface_$rowId'),
          duration: const Duration(milliseconds: 110),
          curve: Curves.easeOut,
          decoration: BoxDecoration(
            color: effectiveColor,
            boxShadow: isHovered
                ? [
                    BoxShadow(
                      color: accentColor.withValues(alpha: 0.10),
                      blurRadius: 8,
                      spreadRadius: 1,
                    ),
                  ]
                : const [],
          ),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.showRowNumbers &&
                    Directionality.of(context) == TextDirection.ltr)
                  _buildNumberCell(
                    Text('${index + 1}'),
                    borderColor,
                  ),
                for (final column in columns)
                  _buildCell(
                    (() {
                      final origIdx = originalIndexById[column.id];
                      if (origIdx != null &&
                          origIdx >= 0 &&
                          origIdx < row.cells.length) {
                        return row.cells[origIdx];
                      }
                      return const SizedBox.shrink();
                    })(),
                    column,
                    borderColor,
                  ),
                if (widget.showRowNumbers &&
                    Directionality.of(context) == TextDirection.rtl)
                  _buildNumberCell(
                    Text('${index + 1}'),
                    borderColor,
                  ),
              ],
            ),
          ),
        ),
        if (isFocused)
          PositionedDirectional(
            start: 0,
            top: 0,
            bottom: 0,
            width: 3,
            child: IgnorePointer(child: Container(color: accentColor)),
          ),
      ],
    );

    // Select immediately, without waiting for the double-tap recognizer.
    final interactiveRow = Listener(
      behavior: HitTestBehavior.opaque,
      onPointerDown: (_) => _focusRow(index),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onSecondaryTapDown: (details) {
          if (row.onSecondaryTapDown != null) {
            row.onSecondaryTapDown!(details.globalPosition);
          } else {
            ContextMenuGate.run(
              () => _showDefaultRowContextMenu(row, details.globalPosition),
            );
          }
        },
        child: row.onTap == null && row.onDoubleTap == null
            ? rowBody
            : Material(
                color: Colors.transparent,
                child: InkWell(
                  // Desktop table convention: one left click only selects
                  // the row (the Listener above already does that). Opening
                  // an item requires a double click. Secondary actions such
                  // as edit/delete/print stay in the context/action menus.
                  onTap: null,
                  onDoubleTap: row.onTap ?? row.onDoubleTap,
                  child: rowBody,
                ),
              ),
      ),
    );

    return KeyedSubtree(
      key: _rowKeyFor(rowId),
      child: MouseRegion(
        cursor: row.onTap != null || row.onDoubleTap != null
            ? SystemMouseCursors.click
            : MouseCursor.defer,
        onEnter: (_) => setState(() => _hoveredRowId = rowId),
        onExit: (_) => setState(() {
          if (_hoveredRowId == rowId) _hoveredRowId = null;
        }),
        child: interactiveRow,
      ),
    );
  }

  Future<void> _showDefaultRowContextMenu(
    ResizableTableRow row,
    Offset globalPosition,
  ) async {
    if (row.onTap == null && row.onDoubleTap == null) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final local = overlay.globalToLocal(globalPosition);
    final x = local.dx.clamp(8.0, overlay.size.width - 8.0).toDouble();
    final y = local.dy.clamp(8.0, overlay.size.height - 8.0).toDouble();
    final languageCode = Localizations.localeOf(context).languageCode;
    final openLabel = switch (languageCode) {
      'ar' => 'فتح',
      'fr' => 'Ouvrir',
      _ => 'Open',
    };
    final editLabel = switch (languageCode) {
      'ar' => 'تعديل',
      'fr' => 'Modifier',
      _ => 'Edit',
    };
    final selected = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        x,
        y,
        overlay.size.width - x,
        overlay.size.height - y,
      ),
      items: [
        if (row.onTap != null)
          PopupMenuItem<String>(
            value: 'open',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.open_in_new_rounded, size: 18),
              title: Text(openLabel),
            ),
          ),
        if (row.onDoubleTap != null)
          PopupMenuItem<String>(
            value: 'edit',
            child: ListTile(
              dense: true,
              leading: Icon(Icons.edit_outlined, size: 18),
              title: Text(editLabel),
            ),
          ),
      ],
    );
    if (!mounted) return;
    if (selected == 'open') row.onTap?.call();
    if (selected == 'edit') row.onDoubleTap?.call();
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
        ),
      ),
      alignment: column.alignment,
      child: DefaultTextStyle.merge(
        style: const TextStyle(fontFamily: 'Cairo', fontSize: 12.5),
        child: ClipRect(child: child),
      ),
    );
  }

  Widget _buildNumberCell(Widget child, Color borderColor) {
    return Container(
      width: _rowNumberWidth,
      constraints: BoxConstraints(minHeight: widget.rowMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: BorderDirectional(
          bottom: BorderSide(color: borderColor, width: 1.0),
        ),
      ),
      alignment: Alignment.center,
      child: DefaultTextStyle.merge(
        style: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        child: ClipRect(child: child),
      ),
    );
  }
}

/// A column of the visibility menu: its checkbox toggles the column without
/// closing the menu.
class _ColumnToggleMenuEntry extends PopupMenuEntry<String> {
  const _ColumnToggleMenuEntry({
    required this.label,
    required this.isVisible,
    required this.canToggle,
    required this.onToggle,
  });

  final Widget label;
  final bool Function() isVisible;
  final bool Function() canToggle;
  final VoidCallback onToggle;

  @override
  double get height => kMinInteractiveDimension;

  @override
  bool represents(String? value) => false;

  @override
  State<_ColumnToggleMenuEntry> createState() => _ColumnToggleMenuEntryState();
}

class _ColumnToggleMenuEntryState extends State<_ColumnToggleMenuEntry> {
  void _toggle() {
    if (!widget.canToggle()) return;
    widget.onToggle();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.canToggle();
    return InkWell(
      onTap: enabled ? _toggle : null,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: widget.height),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Checkbox(
                value: widget.isVisible(),
                onChanged: enabled ? (_) => _toggle() : null,
                visualDensity: VisualDensity.compact,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Opacity(opacity: enabled ? 1 : 0.45, child: widget.label),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
