import 'dart:ui' show PointerDeviceKind;

import 'package:flutter/material.dart';

class ResizableTableColumn {
  final String id;
  final Widget label;
  final double initialWidth;
  final double minWidth;
  final double maxWidth;
  final AlignmentGeometry alignment;

  const ResizableTableColumn({
    required this.id,
    required this.label,
    required this.initialWidth,
    this.minWidth = 80,
    this.maxWidth = 420,
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
  final Color? borderColor;
  final Color? rowColor;
  final double headerMinHeight;
  final double rowMinHeight;
  final EdgeInsets cellPadding;
  final ScrollController? horizontalController;

  const ResizableColumnsTable({
    super.key,
    required this.columns,
    required this.rows,
    this.headerColor,
    this.borderColor,
    this.rowColor,
    this.headerMinHeight = 42,
    this.rowMinHeight = 42,
    this.cellPadding = const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
    this.horizontalController,
  });

  @override
  State<ResizableColumnsTable> createState() => _ResizableColumnsTableState();
}

class _ResizableColumnsTableState extends State<ResizableColumnsTable> {
  final Map<String, double> _widths = {};
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final borderColor =
        widget.borderColor ?? (isDark ? Colors.white12 : Colors.black12);
    final headerColor =
        widget.headerColor ??
        (isDark ? const Color(0xFF1E1E2C) : Colors.blueGrey.shade800);
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
              children: [
                _buildHeader(headerColor, borderColor),
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
    return Container(
      width: _widthFor(column),
      constraints: BoxConstraints(minHeight: widget.headerMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: isLast
            ? null
            : BorderDirectional(end: BorderSide(color: borderColor)),
      ),
      alignment: column.alignment,
      child: Row(
        children: [
          Expanded(child: column.label),
          if (!isLast)
            MouseRegion(
              cursor: SystemMouseCursors.resizeColumn,
              child: GestureDetector(
                behavior: HitTestBehavior.translucent,
                onHorizontalDragUpdate: (details) =>
                    _resize(column, details.delta.dx),
                child: const SizedBox(width: 14, height: 26),
              ),
            ),
        ],
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
                isLast: i == widget.columns.length - 1,
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
    Color borderColor, {
    required bool isLast,
  }) {
    return Container(
      width: _widthFor(column),
      constraints: BoxConstraints(minHeight: widget.rowMinHeight),
      padding: widget.cellPadding,
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: borderColor),
          right: isLast ? BorderSide.none : BorderSide(color: borderColor),
        ),
      ),
      alignment: column.alignment,
      child: child,
    );
  }
}
