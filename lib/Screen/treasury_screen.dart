// ignore_for_file: deprecated_member_use

import 'dart:ui' show PointerDeviceKind;
import 'dart:convert';

import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import 'package:intl/intl.dart';
import '../settings/localization.dart';
import 'receipt_pdf_service.dart';
import '../widgets/resizable_columns_table.dart';
import '../widgets/numeric_filter_search_field.dart';
import '../widgets/table_date_range_filter.dart';

class TreasuryScreen extends StatefulWidget {
  final SqlDatabase db;

  /// وضع العرض فقط — يخفي أزرار الإضافة والحذف
  final bool readOnly;

  const TreasuryScreen({super.key, required this.db, this.readOnly = false});

  bool _isIncomeTransaction(Map<String, dynamic> item) {
    final type = item['transaction_type']?.toString().toLowerCase() ?? '';
    return type == 'encaissement' ||
        type == 'income' ||
        (!type.contains('achat') &&
            !type.contains('purchase') &&
            !type.contains('décaissement') &&
            !type.contains('expense'));
  }

  String _transactionRelation(Map<String, dynamic> item, AppLanguage lang) {
    final entityType = item['entity_type']?.toString().toLowerCase() ?? '';
    final description = item['description']?.toString().toLowerCase() ?? '';
    final isIncome = _isIncomeTransaction(item);

    if (entityType == 'client') {
      return Localization.translate('دفعة مرتبطة بطلبية زبون', lang);
    }
    if (entityType == 'supplier') {
      return Localization.translate(
        isIncome ? 'إرجاع من المورد' : 'دفع للمورد / فاتورة شراء',
        lang,
      );
    }
    if (entityType == 'worker') {
      final isSettlement =
          description.contains('تسوية') ||
          description.contains('weekly') ||
          description.contains('hebdomadaire');
      return Localization.translate(
        isSettlement ? 'تسوية أسبوعية للعامل' : 'دفع للعامل',
        lang,
      );
    }
    if (entityType == 'general') {
      return Localization.translate('مصروف عام غير مرتبط بفاتورة', lang);
    }
    if (item['reference_id'] != null) {
      return Localization.translate('عملية مرتبطة بمرجع', lang);
    }
    return Localization.translate('عملية مستقلة', lang);
  }

  String _transactionDate(Map<String, dynamic> item) {
    final raw = item['created_at']?.toString() ?? '';
    final parsed = DateTime.tryParse(raw);
    return parsed == null ? raw : DateFormat('dd/MM/yyyy HH:mm').format(parsed);
  }

  String _readableText(dynamic value) {
    final text = value?.toString() ?? '';
    if (text.isEmpty ||
        (!text.contains('Ø') && !text.contains('Ã') && !text.contains('Â'))) {
      return text;
    }
    try {
      final repaired = utf8.decode(latin1.encode(text));
      return repaired.contains('�') ? text : repaired;
    } catch (_) {
      return text;
    }
  }

  DataCell _desktopTableCell(
    String value, {
    required double width,
    required Color color,
    bool bold = false,
  }) {
    return DataCell(
      SizedBox(
        width: width,
        child: Text(
          value,
          maxLines: 2,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            color: color,
            fontWeight: bold ? FontWeight.bold : FontWeight.normal,
          ),
        ),
      ),
    );
  }

  Widget _buildDesktopTreasuryTable(
    BuildContext context,
    AppLanguage lang,
    NumberFormat formatter,
    String currency,
    bool isDark,
    List<Map<String, dynamic>> transactions,
    double filteredTotalIncome,
    double filteredTotalExpense,
    bool readOnly,
    bool canEditPayments,
    bool canDeletePayments,
    ScrollController horizontalScrollController,
    ValueChanged<Map<String, dynamic>> onEdit,
    ValueChanged<Map<String, dynamic>> onDelete,
    ValueChanged<Map<String, dynamic>> onReceipt, {
    required TableDateRange dateRange,
    required ValueChanged<TableDateRange> onDateRangeChanged,
    required NumericFilterState numericFilter,
    required ValueChanged<NumericFilterState> onNumericFilterChanged,
    required Map<String, TextEditingController> columnControllers,
    required Map<String, NumericFilterState> columnNumericFilters,
    required VoidCallback onFiltersUpdated,
    required VoidCallback onClearAllFilters,
  }) {
    final textColor = isDark ? Colors.white : Colors.black87;
    final mutedColor = isDark ? Colors.white70 : Colors.black54;
    final headerColor = isDark ? Colors.teal.shade900 : Colors.teal.shade50;
    final borderColor = isDark ? Colors.grey.shade800 : Colors.teal.shade100;

    final hasActiveColumnFilters = dateRange.isActive ||
        numericFilter.isActive ||
        columnNumericFilters.values.any((f) => f.isActive) ||
        columnControllers.values.any((c) => c.text.trim().isNotEmpty);

    final columns = [
      ResizableTableColumn(
        id: 'date',
        label: Text(
          Localization.translate('التاريخ', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'تاريخ...',
          controller: columnControllers['date'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'entered_by',
        label: Text(
          Localization.translate('أدخلها', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'المُدخل...',
          controller: columnControllers['entered_by'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 125,
        minWidth: 85,
        maxWidth: 220,
      ),
      ResizableTableColumn(
        id: 'type',
        label: Text(
          Localization.translate('نوع العملية', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'النوع...',
          controller: columnControllers['type'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 115,
        minWidth: 85,
        maxWidth: 190,
      ),
      ResizableTableColumn(
        id: 'relation',
        label: Text(
          Localization.translate('الارتباط', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'الارتباط...',
          controller: columnControllers['relation'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 190,
        minWidth: 120,
        maxWidth: 360,
      ),
      ResizableTableColumn(
        id: 'method',
        label: Text(
          Localization.translate('طريقة الدفع', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'طريقة الدفع...',
          controller: columnControllers['method'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 145,
        minWidth: 100,
        maxWidth: 250,
      ),
      ResizableTableColumn(
        id: 'desc',
        label: Text(
          Localization.translate('البيان', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'البيان...',
          controller: columnControllers['desc'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 260,
        minWidth: 140,
        maxWidth: 600,
      ),
      ResizableTableColumn(
        id: 'income',
        label: Text(
          Localization.translate('الدفع', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.green),
        ),
        filter: CompactTableFilterField(
          hintText: 'الدفع...',
          isNumeric: true,
          lang: lang,
          initialNumericState: columnNumericFilters['income'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) {
            columnNumericFilters['income'] = f;
            onFiltersUpdated();
          },
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'expense',
        label: Text(
          Localization.translate('السحب', lang),
          style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Colors.red),
        ),
        filter: CompactTableFilterField(
          hintText: 'السحب...',
          isNumeric: true,
          lang: lang,
          initialNumericState: columnNumericFilters['expense'] ?? const NumericFilterState(),
          onNumericFilterChanged: (f) {
            columnNumericFilters['expense'] = f;
            onFiltersUpdated();
          },
        ),
        initialWidth: 130,
        minWidth: 95,
        maxWidth: 240,
      ),
      ResizableTableColumn(
        id: 'caisse',
        label: Text(
          Localization.translate('الصندوق', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        filter: CompactTableFilterField(
          hintText: 'الصندوق...',
          controller: columnControllers['caisse'],
          lang: lang,
          onTextChanged: (_) => onFiltersUpdated(),
        ),
        initialWidth: 135,
        minWidth: 90,
        maxWidth: 230,
      ),
      ResizableTableColumn(
        id: 'receipt',
        label: Text(
          Localization.translate('الإيصال', lang),
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: textColor),
        ),
        initialWidth: 85,
        minWidth: 65,
        maxWidth: 130,
      ),
      ResizableTableColumn(
        id: 'actions',
        label: const Text(
          'Actions',
          style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
        ),
        filter: hasActiveColumnFilters
            ? Center(
                child: InkWell(
                  onTap: onClearAllFilters,
                  borderRadius: BorderRadius.circular(4),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: Colors.red.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(4),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.clear_all, size: 13, color: Colors.red),
                        const SizedBox(width: 2),
                        Text(
                          Localization.translate('مسح', lang),
                          style: const TextStyle(fontSize: 10, color: Colors.red, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                ),
              )
            : null,
        initialWidth: 105,
        minWidth: 85,
        maxWidth: 160,
      ),
    ];

    final rows = transactions.map((item) {
      final isIncome = _isIncomeTransaction(item);
      final amount = (item['amount'] as num?)?.toDouble() ?? 0.0;
      final type = item['transaction_type']?.toString() ?? '';
      final recordedBy = item['recorded_by']?.toString().trim() ?? '';
      final method = _readableText(item['payment_method']).trim();
      final cashbox = _readableText(item['caisse_name']).trim();
      final description = _readableText(item['description']).trim();

      return ResizableTableRow(
        onTap: () {
          if (!readOnly && canEditPayments) {
            onEdit(item);
          } else {
            onReceipt(item);
          }
        },
        cells: [
          // Date
          Text(
            _transactionDate(item),
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: mutedColor),
          ),
          // Entered by
          Text(
            recordedBy.isEmpty || recordedBy == 'system'
                ? Localization.translate('النظام', lang)
                : recordedBy,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: textColor),
          ),
          // Type
          Text(
            type.isEmpty
                ? (isIncome
                    ? Localization.translate('دفع', lang)
                    : Localization.translate('سحب', lang))
                : type,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
          // Relation
          Text(
            _transactionRelation(item, lang),
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12.5, color: textColor),
            overflow: TextOverflow.ellipsis,
          ),
          // Method
          Text(
            method.isEmpty
                ? Localization.translate('نقداً / Espèce', lang)
                : method,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: textColor),
          ),
          // Description
          Text(
            description.isEmpty
                ? Localization.translate('بدون بيان', lang)
                : description,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: textColor),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          // Income
          Text(
            isIncome ? '${formatter.format(amount)} $currency' : '—',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isIncome ? Colors.green.shade700 : mutedColor,
            ),
          ),
          // Expense
          Text(
            isIncome ? '—' : '${formatter.format(amount)} $currency',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: isIncome ? mutedColor : Colors.red.shade700,
            ),
          ),
          // Caisse
          Text(
            cashbox.isEmpty ? Localization.translate('الصندوق الرئيسي', lang) : cashbox,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: textColor),
          ),
          // Receipt
          IconButton(
            tooltip: Localization.translate('خيارات الوصل', lang),
            icon: const Icon(Icons.receipt_long_outlined, size: 19),
            color: isDark ? Colors.tealAccent : Colors.teal,
            onPressed: () => onReceipt(item),
          ),
          // Actions
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!readOnly && canEditPayments)
                IconButton(
                  tooltip: 'Modifier',
                  icon: const Icon(Icons.edit_outlined, size: 19),
                  color: Colors.blue,
                  onPressed: () => onEdit(item),
                ),
              if (!readOnly && canDeletePayments)
                IconButton(
                  tooltip: 'Supprimer',
                  icon: const Icon(Icons.delete_outline, size: 19),
                  color: Colors.red,
                  onPressed: () => onDelete(item),
                ),
            ],
          ),
        ],
      );
    }).toList();

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      decoration: BoxDecoration(
        color: isDark ? Colors.grey.shade900 : Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: borderColor),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Header Summary Bar ──
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: headerColor,
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Wrap(
              alignment: WrapAlignment.spaceBetween,
              crossAxisAlignment: WrapCrossAlignment.center,
              runSpacing: 6,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.table_chart_rounded, size: 20, color: Colors.teal),
                    const SizedBox(width: 8),
                    Text(
                      Localization.translate('سجل عمليات الصندوق', lang),
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontWeight: FontWeight.bold,
                        fontSize: 13.5,
                        color: isDark ? Colors.tealAccent : Colors.teal.shade900,
                      ),
                    ),
                  ],
                ),
                Text(
                  '${Localization.translate('الدفع', lang)}: ${formatter.format(filteredTotalIncome)} $currency   •   '
                  '${Localization.translate('السحب', lang)}: ${formatter.format(filteredTotalExpense)} $currency   •   '
                  '${Localization.translate('الرصيد', lang)}: ${formatter.format(filteredTotalIncome - filteredTotalExpense)} $currency',
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 12.5,
                    fontWeight: FontWeight.bold,
                    color: textColor,
                  ),
                ),
              ],
            ),
          ),

          // ── Desktop Filters Bar (Date Range + Numeric Operator Search) ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: isDark ? const Color(0xFF1E293B) : const Color(0xFFF8FAFC),
              border: Border(bottom: BorderSide(color: borderColor)),
            ),
            child: Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              alignment: WrapAlignment.spaceBetween,
              spacing: 12,
              runSpacing: 8,
              children: [
                // Date Range Filter Bar
                TableDateRangeFilterBar(
                  initialRange: dateRange,
                  lang: lang,
                  compact: true,
                  onRangeChanged: onDateRangeChanged,
                ),

                // Numeric Amount Search with Comparison Operators
                NumericFilterSearchField(
                  hintText: Localization.translate('بحث بالمبلغ (=, >, <, ≥, ≤, ≠)...', lang),
                  lang: lang,
                  initialState: numericFilter,
                  width: 300,
                  onFilterChanged: onNumericFilterChanged,
                ),
              ],
            ),
          ),

          // ── Resizable Desktop Table with zero vertical overflow ──
          Expanded(
            child: transactions.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24.0),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.search_off_rounded, size: 48, color: mutedColor),
                          const SizedBox(height: 8),
                          Text(
                            Localization.translate('لا توجد عمليات مطابقة لشروط الفلترة الحالية', lang),
                            style: TextStyle(fontFamily: 'Cairo', color: mutedColor),
                          ),
                        ],
                      ),
                    ),
                  )
                : Container(
                    decoration: BoxDecoration(
                      border: Border.all(color: borderColor),
                    ),
                    child: SingleChildScrollView(
                      child: ResizableColumnsTable(
                        columns: columns,
                        rows: rows,
                        headerColor: headerColor,
                        filterRowColor: isDark ? const Color(0xFF1A1A26) : const Color(0xFFF1F5F9),
                        borderColor: borderColor,
                        rowColor: isDark ? const Color(0xFF171721) : Colors.white,
                        horizontalController: horizontalScrollController,
                        headerMinHeight: 40,
                        filterRowMinHeight: 34,
                        rowMinHeight: 46,
                      ),
                    ),
                  ),
          ),
        ],
      ),
    );
  }
  @override
  State<TreasuryScreen> createState() => _TreasuryScreenState();
}

class _TreasuryScreenState extends State<TreasuryScreen> {
  List<Map<String, dynamic>> _allTransactions = [];
  List<Map<String, dynamic>> _filteredTransactions = [];
  bool _isLoading = false;
  double _totalBalance = 0.0;
  String _searchQuery = '';
  List<String> _caisseNames = [];
  String _selectedCaisse = 'الكل';
  String _selectedTypeFilter = 'all'; // 'all', 'income', 'expense'
  String _selectedCategoryFilter = 'all'; // 'all', 'general_expenses'
  double _filteredTotalIncome = 0.0;
  double _filteredTotalExpense = 0.0;
  TableDateRange _dateRange = const TableDateRange();
  NumericFilterState _numericFilter = const NumericFilterState();
  final Map<String, TextEditingController> _treasuryColumnControllers = {
    'date': TextEditingController(),
    'entered_by': TextEditingController(),
    'type': TextEditingController(),
    'relation': TextEditingController(),
    'method': TextEditingController(),
    'desc': TextEditingController(),
    'caisse': TextEditingController(),
  };
  final Map<String, NumericFilterState> _treasuryNumericFilters = {};
  bool _showSearch = false;
  bool _showFilters = false;
  final ScrollController _desktopTableScrollController = ScrollController();

  List<Map<String, dynamic>> _clients = [];
  List<Map<String, dynamic>> _workers = [];
  List<Map<String, dynamic>> _suppliers = [];

  @override
  void initState() {
    super.initState();
    _loadData();
    _loadEntities();
  }

  @override
  void dispose() {
    _desktopTableScrollController.dispose();
    super.dispose();
  }

  Future<void> _loadEntities() async {
    final clients = await widget.db.readClient();
    final workers = await widget.db.readEmployees();
    final suppliers = await widget.db.readSuppliers();
    if (mounted) {
      setState(() {
        _clients = clients;
        _workers = workers;
        _suppliers = suppliers;
      });
    }
  }

  Future<void> _loadData() async {
    if (mounted) setState(() => _isLoading = true);
    try {
      await widget.db.migrateLegacyTreasuryRecords();

      final rawData = await widget.db.readTreasury();
      final data = rawData
          .map(
            (row) => <String, dynamic>{
              ...row,
              'caisse_name': widget._readableText(row['caisse_name']),
              'payment_method': widget._readableText(row['payment_method']),
              'description': widget._readableText(row['description']),
              'recorded_by': widget._readableText(row['recorded_by']),
            },
          )
          .toList();
      final caisses = await widget.db.readCaisses();
      final caisseNames = caisses
          .map((c) => widget._readableText(c['name']))
          .toList();
      if (caisseNames.isEmpty) {
        caisseNames.add('الصندوق الرئيسي');
      }

      double balance = 0.0;
      for (var row in data) {
        final cName = row['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
        if (_selectedCaisse != 'الكل' && cName != _selectedCaisse) {
          continue;
        }
        final type = row['transaction_type']?.toString() ?? '';
        if (type == 'Encaissement' || type == 'income') {
          balance += (row['amount'] as num?)?.toDouble() ?? 0.0;
        } else if (type == 'Décaissement' ||
            type == 'DÃ©caissement' ||
            type == 'expense') {
          balance -= (row['amount'] as num?)?.toDouble() ?? 0.0;
        } else {
          if (type.contains('Achat') || type.contains('Purchase')) {
            balance -= (row['amount'] as num?)?.toDouble() ?? 0.0;
          } else {
            balance += (row['amount'] as num?)?.toDouble() ?? 0.0;
          }
        }
      }

      if (mounted) {
        setState(() {
          _allTransactions = data;
          _caisseNames = caisseNames;
          _totalBalance = balance;
          _applyFilter();
        });
      }
    } catch (e) {
      debugPrint('Error loading treasury: $e');
    } finally {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  void _applyFilter() {
    List<Map<String, dynamic>> filtered = _allTransactions;

    // 1. Caisse filter
    if (_selectedCaisse != 'الكل') {
      filtered = filtered.where((t) {
        final cName = t['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
        return cName == _selectedCaisse;
      }).toList();
    }

    // 2. Type Filter (income / expense)
    if (_selectedTypeFilter != 'all') {
      filtered = filtered.where((t) {
        final tType = t['transaction_type']?.toString() ?? '';
        final isInc =
            tType == 'Encaissement' ||
            tType == 'income' ||
            (!tType.contains('Achat') &&
                !tType.contains('Purchase') &&
                !tType.contains('Décaissement') &&
                !tType.contains('DÃ©caissement') &&
                !tType.contains('expense'));
        if (_selectedTypeFilter == 'income') {
          return isInc;
        } else {
          return !isInc;
        }
      }).toList();
    }

    // 3. Category Filter (general expenses/faux frais/additional costs)
    if (_selectedCategoryFilter == 'general_expenses') {
      filtered = filtered.where((t) {
        final entityType = t['entity_type']?.toString();
        final desc = (t['description'] ?? '').toString().toLowerCase();

        final isGeneral =
            entityType == 'General' ||
            desc.contains('dépens') ||
            desc.contains('مصاريف') ||
            desc.contains('مازوت') ||
            desc.contains('سيارة') ||
            desc.contains('تصليح') ||
            desc.contains('répar') ||
            desc.contains('carburant');

        return isGeneral;
      }).toList();
    }

    // Date Range filter
    if (_dateRange.isActive) {
      filtered = filtered.where((t) {
        final dStr = t['created_at']?.toString() ?? '';
        final d = DateTime.tryParse(dStr);
        return _dateRange.isWithinRange(d);
      }).toList();
    }

    // Numeric Operator Filter on Amount
    if (_numericFilter.isActive) {
      filtered = filtered.where((t) {
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return _numericFilter.matches(amt);
      }).toList();
    }

    // Per-column numeric filters (Income, Expense)
    if (_treasuryNumericFilters['income']?.isActive == true) {
      filtered = filtered.where((t) {
        final isInc = widget._isIncomeTransaction(t);
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return isInc ? _treasuryNumericFilters['income']!.matches(amt) : _treasuryNumericFilters['income']!.matches(0);
      }).toList();
    }
    if (_treasuryNumericFilters['expense']?.isActive == true) {
      filtered = filtered.where((t) {
        final isInc = widget._isIncomeTransaction(t);
        final amt = (t['amount'] as num?)?.toDouble() ?? 0.0;
        return !isInc ? _treasuryNumericFilters['expense']!.matches(amt) : _treasuryNumericFilters['expense']!.matches(0);
      }).toList();
    }

    // Per-column text filters
    for (final entry in _treasuryColumnControllers.entries) {
      final val = entry.value.text.trim().toLowerCase();
      if (val.isEmpty) continue;
      switch (entry.key) {
        case 'date':
          filtered = filtered.where((t) => widget._transactionDate(t).toLowerCase().contains(val)).toList();
          break;
        case 'entered_by':
          filtered = filtered.where((t) => (t['recorded_by'] ?? '').toString().toLowerCase().contains(val)).toList();
          break;
        case 'type':
          filtered = filtered.where((t) => (t['transaction_type'] ?? '').toString().toLowerCase().contains(val)).toList();
          break;
        case 'relation':
          filtered = filtered.where((t) => widget._transactionRelation(t, AppLanguage.arabic).toLowerCase().contains(val)).toList();
          break;
        case 'method':
          filtered = filtered.where((t) => (t['payment_method'] ?? '').toString().toLowerCase().contains(val)).toList();
          break;
        case 'desc':
          filtered = filtered.where((t) => (t['description'] ?? '').toString().toLowerCase().contains(val)).toList();
          break;
        case 'caisse':
          filtered = filtered.where((t) => (t['caisse_name'] ?? '').toString().toLowerCase().contains(val)).toList();
          break;
      }
    }

    // 4. Search filter
    if (_searchQuery.isNotEmpty) {
      final search = _searchQuery.trim().toLowerCase();
      filtered = filtered.where((t) {
        final desc = (t['description'] ?? '').toString().toLowerCase();
        final amount = (t['amount'] ?? '').toString().toLowerCase();
        final phone = (t['phone'] ?? '').toString().toLowerCase();
        final recorded = (t['recorded_by'] ?? '').toString().toLowerCase();
        final date = (t['created_at'] ?? '').toString().toLowerCase();
        final tType = (t['transaction_type'] ?? '').toString().toLowerCase();
        final pMethod = (t['payment_method'] ?? '').toString().toLowerCase();
        final cName = (t['caisse_name'] ?? '').toString().toLowerCase();

        return desc.contains(search) ||
            amount.contains(search) ||
            phone.contains(search) ||
            recorded.contains(search) ||
            date.contains(search) ||
            tType.contains(search) ||
            pMethod.contains(search) ||
            cName.contains(search);
      }).toList();
    }

    // Calculate sum of filtered records
    double inc = 0.0;
    double exp = 0.0;
    for (var row in filtered) {
      final tType = row['transaction_type']?.toString() ?? '';
      final isInc =
          tType == 'Encaissement' ||
          tType == 'income' ||
          (!tType.contains('Achat') &&
              !tType.contains('Purchase') &&
              !tType.contains('Décaissement') &&
              !tType.contains('DÃ©caissement') &&
              !tType.contains('expense'));
      final amt = (row['amount'] as num?)?.toDouble() ?? 0.0;
      if (isInc) {
        inc += amt;
      } else {
        exp += amt;
      }
    }

    setState(() {
      _filteredTransactions = filtered;
      _filteredTotalIncome = inc;
      _filteredTotalExpense = exp;
    });
  }

  Widget _highlightText(String text, String query, TextStyle defaultStyle) {
    if (query.isEmpty) {
      return Text(text, style: defaultStyle);
    }

    final String textLower = text.toLowerCase();
    final String queryLower = query.toLowerCase();

    final List<TextSpan> spans = [];
    int start = 0;
    int indexOfMatch;

    while ((indexOfMatch = textLower.indexOf(queryLower, start)) != -1) {
      if (indexOfMatch > start) {
        spans.add(
          TextSpan(
            text: text.substring(start, indexOfMatch),
            style: defaultStyle,
          ),
        );
      }

      spans.add(
        TextSpan(
          text: text.substring(indexOfMatch, indexOfMatch + query.length),
          style: defaultStyle.copyWith(
            backgroundColor: Colors.yellow.shade200,
            color: Colors.black87,
            fontWeight: FontWeight.bold,
          ),
        ),
      );

      start = indexOfMatch + query.length;
    }

    if (start < text.length) {
      spans.add(TextSpan(text: text.substring(start), style: defaultStyle));
    }

    return RichText(
      text: TextSpan(children: spans),
      overflow: TextOverflow.ellipsis,
      maxLines: 2,
    );
  }

  Future<void> _deleteTransaction(Map<String, dynamic> item) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate('تأكيد الحذف', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          Localization.translate('هل أنت متأكد من حذف هذه المعاملة؟', lang),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(
              Localization.translate('إلغاء', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(
              Localization.translate('حذف', lang),
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.red,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
    );

    if (confirm == true) {
      final id = item['id'] as int;
      await widget.db.deleteTreasury(id);
      _loadData();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate('تم حذف المعاملة بنجاح', lang),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
        );
      }
    }
  }

  void _showEditTransactionDialog(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final id = item['id'] as int;
    final amountCtrl = TextEditingController(
      text: item['amount']?.toString() ?? '',
    );
    final descCtrl = TextEditingController(text: item['description'] ?? '');
    String selectedCaisse =
        item['caisse_name']?.toString() ?? 'الصندوق الرئيسي';
    String selectedPaymentMethod =
        item['payment_method']?.toString() ?? 'نقداً / Espèce';

    DateTime selectedDate;
    try {
      selectedDate = DateTime.parse(item['created_at']);
    } catch (_) {
      selectedDate = DateTime.now();
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('تعديل المعاملة', lang),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  decoration: InputDecoration(
                    labelText: Localization.translate('المبلغ (د.ج)', lang),
                    prefixIcon: const Icon(Icons.attach_money),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 10),
                Builder(
                  builder: (ctx) {
                    final canChangeDate = Provider.of<AppSettingsProvider>(
                      context,
                      listen: false,
                    ).canChangeTransactionDates();
                    return InkWell(
                      onTap: canChangeDate
                          ? () async {
                              final date = await showDatePicker(
                                context: context,
                                initialDate: selectedDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (date != null && mounted) {
                                final time = await showTimePicker(
                                  context: context,
                                  initialTime: TimeOfDay.fromDateTime(
                                    selectedDate,
                                  ),
                                );
                                if (time != null) {
                                  setStateDialog(() {
                                    selectedDate = DateTime(
                                      date.year,
                                      date.month,
                                      date.day,
                                      time.hour,
                                      time.minute,
                                    );
                                  });
                                }
                              }
                            }
                          : null,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.grey.shade400),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_today,
                              size: 18,
                              color: canChangeDate ? Colors.teal : Colors.grey,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              DateFormat(
                                'dd/MM/yyyy  HH:mm',
                              ).format(selectedDate),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: canChangeDate ? null : Colors.grey,
                              ),
                            ),
                            if (!canChangeDate) ...[
                              const Spacer(),
                              const Icon(
                                Icons.lock,
                                size: 16,
                                color: Colors.grey,
                              ),
                            ],
                          ],
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _caisseNames.contains(selectedCaisse)
                      ? selectedCaisse
                      : (_caisseNames.isNotEmpty ? _caisseNames.first : null),
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر الصندوق', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items: _caisseNames
                      .map(
                        (name) => DropdownMenuItem<String>(
                          value: name,
                          child: Text(
                            Localization.translate(name, lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      )
                      .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedCaisse = val!);
                  },
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: selectedPaymentMethod,
                  decoration: InputDecoration(
                    labelText: Localization.translate('طريقة الدفع', lang),
                    border: const OutlineInputBorder(),
                  ),
                  items:
                      [
                            'نقداً / Espèce',
                            'شيك / Chèque',
                            'شيك مصدق / Chèque de banque',
                            'تحويل بنكي / Virement',
                            'بطاقة بنكية / CIB',
                            'CCP / حساب جاري',
                            'بريدي موب / BaridiMob',
                          ]
                          .map(
                            (method) => DropdownMenuItem<String>(
                              value: method,
                              child: Text(
                                method,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                  onChanged: (val) {
                    setStateDialog(() => selectedPaymentMethod = val!);
                  },
                ),
                const SizedBox(height: 10),
                TextField(
                  controller: descCtrl,
                  maxLines: 2,
                  decoration: InputDecoration(
                    labelText: Localization.translate('البيان / السبب', lang),
                    prefixIcon: const Icon(Icons.notes),
                    border: const OutlineInputBorder(),
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
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            TextButton(
              onPressed: () async {
                final double? newAmt = double.tryParse(amountCtrl.text);
                if (newAmt == null || newAmt <= 0) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        Localization.translate('يرجى إدخال مبلغ صحيح', lang),
                      ),
                    ),
                  );
                  return;
                }

                Navigator.pop(context);
                await widget.db.updateTreasury(
                  id,
                  newAmount: newAmt,
                  newDescription: descCtrl.text,
                  newCaisse: selectedCaisse,
                  newPaymentMethod: selectedPaymentMethod,
                  newCreatedAt: selectedDate.toIso8601String(),
                );
                _loadData();
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      Localization.translate('تم تعديل المعاملة بنجاح', lang),
                    ),
                  ),
                );
              },
              child: Text(
                Localization.translate('حفظ', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showReceiptOptions(BuildContext context, Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.print, color: Colors.teal),
                title: Text(
                  '${Localization.translate('طباعة الوصل', lang)} / Imprimer',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.printReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.share, color: Colors.orange),
                title: Text(
                  '${Localization.translate('مشاركة', lang)} / Partager',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.shareReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              ListTile(
                leading: const Icon(Icons.download, color: Colors.blue),
                title: Text(
                  '${Localization.translate('حفظ الوصل', lang)} / Enregistrer',
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                  ),
                ),
                onTap: () async {
                  Navigator.pop(ctx);
                  await ReceiptPdfService.saveReceiptWithFeedback(
                    item,
                    context,
                  );
                },
              ),
              if (Provider.of<AppSettingsProvider>(
                context,
                listen: false,
              ).canEditPayments())
                ListTile(
                  leading: const Icon(Icons.edit, color: Colors.blueGrey),
                  title: Text(
                    '${Localization.translate('تعديل المعاملة', lang)} / Modifier',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _showEditTransactionDialog(item);
                  },
                ),
              if (!widget.readOnly &&
                  Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  ).canDeletePayments())
                ListTile(
                  leading: const Icon(Icons.delete, color: Colors.red),
                  title: Text(
                    '${Localization.translate('حذف المعاملة', lang)} / Supprimer',
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteTransaction(item);
                  },
                ),
            ],
          ),
        );
      },
    );
  }

  void _showManageCaissesDialog() {
    final nameCtrl = TextEditingController();
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setStateDialog) {
            return AlertDialog(
              title: Text(
                Localization.translate('إدارة الصناديق والحسابات', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                height: 350,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: TextField(
                            controller: nameCtrl,
                            decoration: InputDecoration(
                              labelText: Localization.translate(
                                'اسم صندوق جديد',
                                lang,
                              ),
                              border: const OutlineInputBorder(),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        ElevatedButton(
                          onPressed: () async {
                            final name = nameCtrl.text.trim();
                            if (name.isNotEmpty) {
                              await widget.db.insertCaisse(name);
                              nameCtrl.clear();
                              setStateDialog(() {});
                              _loadData();
                            }
                          },
                          child: Text(Localization.translate('إضافة', lang)),
                        ),
                      ],
                    ),
                    const Divider(height: 24),
                    Text(
                      Localization.translate(
                        'الصناديق الحالية (اضغط للتعديل أو الحذف):',
                        lang,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        color: Colors.grey,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Expanded(
                      child: FutureBuilder<List<Map<String, dynamic>>>(
                        future: widget.db.readCaisses(),
                        builder: (context, snapshot) {
                          if (!snapshot.hasData) {
                            return const Center(
                              child: CircularProgressIndicator(),
                            );
                          }
                          final list = snapshot.data!;
                          return ListView.builder(
                            shrinkWrap: true,
                            itemCount: list.length,
                            itemBuilder: (context, idx) {
                              final item = list[idx];
                              final id = item['id'] as int;
                              final rawName = item['name'].toString();
                              final name = widget._readableText(rawName);
                              return Card(
                                child: ListTile(
                                  title: Text(
                                    Localization.translate(name, lang),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  trailing: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      IconButton(
                                        icon: const Icon(
                                          Icons.edit,
                                          color: Colors.blue,
                                        ),
                                        onPressed: () async {
                                          final editCtrl =
                                              TextEditingController(text: name);
                                          final newName = await showDialog<String>(
                                            context: context,
                                            builder: (ctx) => AlertDialog(
                                              title: Text(
                                                Localization.translate(
                                                  'تعديل اسم الصندوق',
                                                  lang,
                                                ),
                                              ),
                                              content: TextField(
                                                controller: editCtrl,
                                                decoration: InputDecoration(
                                                  labelText:
                                                      Localization.translate(
                                                        'الاسم الجديد',
                                                        lang,
                                                      ),
                                                  border:
                                                      const OutlineInputBorder(),
                                                ),
                                              ),
                                              actions: [
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(ctx),
                                                  child: Text(
                                                    Localization.translate(
                                                      'إلغاء',
                                                      lang,
                                                    ),
                                                  ),
                                                ),
                                                TextButton(
                                                  onPressed: () =>
                                                      Navigator.pop(
                                                        ctx,
                                                        editCtrl.text.trim(),
                                                      ),
                                                  child: Text(
                                                    Localization.translate(
                                                      'حفظ',
                                                      lang,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          );
                                          if (newName != null &&
                                              newName.isNotEmpty &&
                                              newName != name) {
                                            await widget.db.updateCaisseName(
                                              id,
                                              newName,
                                              rawName,
                                            );
                                            setStateDialog(() {});
                                            _loadData();
                                          }
                                        },
                                      ),
                                      if (list.length > 1 && !widget.readOnly)
                                        IconButton(
                                          icon: const Icon(
                                            Icons.delete,
                                            color: Colors.red,
                                          ),
                                          onPressed: () async {
                                            final confirm = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx) => AlertDialog(
                                                title: Text(
                                                  Localization.translate(
                                                    'تأكيد الحذف',
                                                    lang,
                                                  ),
                                                ),
                                                content: Text(
                                                  '${Localization.translate('هل أنت متأكد من حذف الصندوق', lang)} "${Localization.translate(name, lang)}"؟ ${Localization.translate('سيتم نقل معاملاته تلقائياً للصندوق الآخر.', lang)}',
                                                ),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          false,
                                                        ),
                                                    child: Text(
                                                      Localization.translate(
                                                        'إلغاء',
                                                        lang,
                                                      ),
                                                    ),
                                                  ),
                                                  TextButton(
                                                    onPressed: () =>
                                                        Navigator.pop(
                                                          ctx,
                                                          true,
                                                        ),
                                                    child: Text(
                                                      Localization.translate(
                                                        'حذف',
                                                        lang,
                                                      ),
                                                      style: const TextStyle(
                                                        color: Colors.red,
                                                      ),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (confirm == true) {
                                              await widget.db.deleteCaisse(
                                                id,
                                                rawName,
                                              );
                                              setStateDialog(() {});
                                              _loadData();
                                            }
                                          },
                                        ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showAddTransactionDialog() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final amountCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    String type = 'Encaissement';
    String entityType = 'Client';
    int? selectedEntityId;
    double oldBalance = 0.0;
    double newBalance = 0.0;
    bool loadingBalance = false;
    DateTime selectedDate = DateTime.now();
    String selectedCaisse = _caisseNames.isNotEmpty
        ? _caisseNames.first
        : 'الصندوق الرئيسي';
    String selectedPaymentMethod = 'نقداً / Espèce';

    Future<void> loadBalance(
      StateSetter setStateDialog,
      String eType,
      int eId,
    ) async {
      setStateDialog(() => loadingBalance = true);
      double bal = 0.0;
      if (eType == 'Client') {
        bal = await widget.db.getClientBalance(eId);
      } else if (eType == 'Supplier') {
        bal = await widget.db.getSupplierBalance(eId);
      } else if (eType == 'Worker') {
        bal = await widget.db.getWorkerBalance(eId);
      }
      setStateDialog(() {
        oldBalance = bal;
        final amount = double.tryParse(amountCtrl.text) ?? 0.0;
        newBalance = type == 'Encaissement'
            ? oldBalance - amount
            : oldBalance + amount;
        loadingBalance = false;
      });
    }

    void recalcNewBalance(StateSetter setStateDialog) {
      final amount = double.tryParse(amountCtrl.text) ?? 0.0;
      setStateDialog(() {
        newBalance = type == 'Encaissement'
            ? oldBalance - amount
            : oldBalance + amount;
      });
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('إضافة معاملة للصندوق', lang),
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 500,
              maxHeight: MediaQuery.of(context).size.height * 0.75,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: type,
                    decoration: InputDecoration(
                      labelText: Localization.translate('نوع المعاملة', lang),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'Encaissement',
                        child: Text(
                          Localization.translate('قبض / Encaissement', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'Décaissement',
                        child: Text(
                          Localization.translate('دفع / Décaissement', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        type = val!;
                        if (type == 'Encaissement') {
                          entityType = 'Client';
                        } else {
                          entityType = 'Supplier';
                        }
                        selectedEntityId = null;
                        phoneCtrl.clear();
                        oldBalance = 0.0;
                        newBalance = 0.0;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: entityType,
                    decoration: InputDecoration(
                      labelText: Localization.translate('نوع الجهة', lang),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: [
                      if (type == 'Encaissement') ...[
                        DropdownMenuItem(
                          value: 'Client',
                          child: Text(
                            Localization.translate('زبون', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Supplier',
                          child: Text(
                            Localization.translate('مورد (استرجاع)', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ] else ...[
                        DropdownMenuItem(
                          value: 'Supplier',
                          child: Text(
                            Localization.translate('مورد', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'Worker',
                          child: Text(
                            Localization.translate('عامل', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        DropdownMenuItem(
                          value: 'General',
                          child: Text(
                            Localization.translate('مصاريف عامة', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ],
                    onChanged: (val) {
                      setStateDialog(() {
                        entityType = val!;
                        selectedEntityId = null;
                        phoneCtrl.clear();
                        oldBalance = 0.0;
                        newBalance = 0.0;
                      });
                    },
                  ),
                  const SizedBox(height: 12),

                  if (entityType == 'Client') ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedEntityId,
                      hint: Text(
                        Localization.translate('اختر الزبون', lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر الزبون', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: _clients
                          .map(
                            (c) => DropdownMenuItem<int>(
                              value: c['id'] as int,
                              child: Text(
                                '${c['firstname']} ${c['lastname']}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() => selectedEntityId = val);
                        if (val != null) {
                          final client = _clients.firstWhere(
                            (c) => c['id'] == val,
                          );
                          phoneCtrl.text = client['phone1'] ?? '';
                          loadBalance(setStateDialog, 'Client', val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ] else if (entityType == 'Supplier') ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedEntityId,
                      hint: Text(
                        Localization.translate('اختر المورد', lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر المورد', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: _suppliers
                          .map(
                            (s) => DropdownMenuItem<int>(
                              value: s['id'] as int,
                              child: Text(
                                s['name']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() => selectedEntityId = val);
                        if (val != null) {
                          final supplier = _suppliers.firstWhere(
                            (s) => s['id'] == val,
                          );
                          phoneCtrl.text = supplier['phone'] ?? '';
                          loadBalance(setStateDialog, 'Supplier', val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ] else if (entityType == 'Worker') ...[
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      value: selectedEntityId,
                      hint: Text(
                        Localization.translate('اختر العامل', lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر العامل', lang),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                      items: _workers
                          .map(
                            (w) => DropdownMenuItem<int>(
                              value: w['id'] as int,
                              child: Text(
                                w['name']?.toString() ?? '-',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        setStateDialog(() => selectedEntityId = val);
                        if (val != null) {
                          loadBalance(setStateDialog, 'Worker', val);
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (entityType != 'General') ...[
                    TextField(
                      controller: phoneCtrl,
                      keyboardType: TextInputType.phone,
                      decoration: InputDecoration(
                        labelText: Localization.translate('رقم الهاتف', lang),
                        prefixIcon: const Icon(Icons.phone),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  if (entityType != 'General' && selectedEntityId != null) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: Theme.of(context).brightness == Brightness.dark
                            ? Colors.grey.shade900
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: loadingBalance
                          ? const Center(
                              child: SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text(
                                  Localization.translate(
                                    'الرصيد القديم:',
                                    lang,
                                  ),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13,
                                  ),
                                ),
                                Flexible(
                                  child: Text(
                                    '${NumberFormat('#,##0.00').format(oldBalance.abs())} د.ج'
                                    '  (${oldBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 13,
                                      color: oldBalance > 0
                                          ? Colors.orange.shade800
                                          : Colors.green.shade700,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  TextField(
                    controller: amountCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      labelText: Localization.translate('المبلغ (د.ج)', lang),
                      prefixIcon: const Icon(Icons.attach_money),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    onChanged: (_) => recalcNewBalance(setStateDialog),
                  ),
                  const SizedBox(height: 12),

                  if (entityType != 'General' &&
                      selectedEntityId != null &&
                      amountCtrl.text.isNotEmpty) ...[
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 10,
                      ),
                      decoration: BoxDecoration(
                        color: newBalance <= 0
                            ? Colors.green.withValues(alpha: 0.1)
                            : Colors.orange.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: newBalance <= 0
                              ? Colors.green.shade300
                              : Colors.orange.shade300,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            Localization.translate('الرصيد الجديد:', lang),
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              '${NumberFormat('#,##0.00').format(newBalance.abs())} د.ج'
                              '  (${newBalance >= 0 ? Localization.translate("مدين", lang) : Localization.translate("دائن", lang)})',
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 13,
                                color: newBalance > 0
                                    ? Colors.orange.shade800
                                    : Colors.green.shade700,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],

                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: _caisseNames.contains(selectedCaisse)
                        ? selectedCaisse
                        : (_caisseNames.isNotEmpty ? _caisseNames.first : null),
                    decoration: InputDecoration(
                      labelText: Localization.translate('اختر الصندوق', lang),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items: _caisseNames
                        .map(
                          (name) => DropdownMenuItem<String>(
                            value: name,
                            child: Text(
                              Localization.translate(name, lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedCaisse = val!);
                    },
                  ),
                  const SizedBox(height: 12),

                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    value: selectedPaymentMethod,
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'طريقة الدفع / التحويل',
                        lang,
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                    items:
                        [
                              'نقداً / Espèce',
                              'شيك / Chèque',
                              'شيك مصدق / Chèque de banque',
                              'تحويل بنكي / Virement',
                              'بطاقة بنكية / CIB',
                              'CCP / حساب جاري',
                              'بريدي موب / BaridiMob',
                            ]
                            .map(
                              (method) => DropdownMenuItem<String>(
                                value: method,
                                child: Text(
                                  method,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                    onChanged: (val) {
                      setStateDialog(() => selectedPaymentMethod = val!);
                    },
                  ),
                  const SizedBox(height: 12),

                  Builder(
                    builder: (ctx) {
                      final canChangeDate = Provider.of<AppSettingsProvider>(
                        context,
                        listen: false,
                      ).canChangeTransactionDates();
                      return InkWell(
                        onTap: canChangeDate
                            ? () async {
                                final date = await showDatePicker(
                                  context: context,
                                  initialDate: selectedDate,
                                  firstDate: DateTime(2020),
                                  lastDate: DateTime(2030),
                                );
                                if (date != null && mounted) {
                                  final time = await showTimePicker(
                                    context: context,
                                    initialTime: TimeOfDay.fromDateTime(
                                      selectedDate,
                                    ),
                                  );
                                  if (time != null) {
                                    setStateDialog(() {
                                      selectedDate = DateTime(
                                        date.year,
                                        date.month,
                                        date.day,
                                        time.hour,
                                        time.minute,
                                      );
                                    });
                                  }
                                }
                              }
                            : null,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 12,
                          ),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade400),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                Icons.calendar_today,
                                size: 18,
                                color: canChangeDate
                                    ? Colors.teal
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                DateFormat(
                                  'dd/MM/yyyy  HH:mm',
                                ).format(selectedDate),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  color: canChangeDate ? null : Colors.grey,
                                ),
                              ),
                              if (!canChangeDate) ...[
                                const Spacer(),
                                const Icon(
                                  Icons.lock,
                                  size: 16,
                                  color: Colors.grey,
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                  const SizedBox(height: 12),

                  TextField(
                    controller: descCtrl,
                    maxLines: 2,
                    decoration: InputDecoration(
                      labelText: Localization.translate('البيان / السبب', lang),
                      prefixIcon: const Icon(Icons.notes),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(
                Localization.translate('إلغاء', lang),
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save, color: Colors.white),
              onPressed: () async {
                final amountText = amountCtrl.text.trim();
                if (amountText.isEmpty) return;
                final amount = double.tryParse(amountText) ?? 0.0;
                if (amount <= 0) return;

                final settings = Provider.of<AppSettingsProvider>(
                  context,
                  listen: false,
                );
                final String userName = settings.userDisplayName;

                String finalDesc = descCtrl.text.trim();
                if (entityType == 'Client' && selectedEntityId != null) {
                  final client = _clients.firstWhere(
                    (c) => c['id'] == selectedEntityId,
                  );
                  finalDesc =
                      'من الزبون: ${client['firstname']} ${client['lastname']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                } else if (entityType == 'Supplier' &&
                    selectedEntityId != null) {
                  final supplier = _suppliers.firstWhere(
                    (s) => s['id'] == selectedEntityId,
                  );
                  finalDesc =
                      '${type == 'Encaissement' ? 'استرجاع من المورد' : 'للمورد'}: ${supplier['name']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                } else if (entityType == 'Worker' && selectedEntityId != null) {
                  final worker = _workers.firstWhere(
                    (w) => w['id'] == selectedEntityId,
                  );
                  finalDesc =
                      'إلى العامل: ${worker['name']}'
                      '${finalDesc.isNotEmpty ? ' - $finalDesc' : ''}';
                }

                final calcNewBalance = entityType == 'General'
                    ? 0.0
                    : (type == 'Encaissement'
                          ? oldBalance - amount
                          : oldBalance + amount);

                await widget.db.insertTreasury(
                  type,
                  amount,
                  finalDesc,
                  entityType: entityType,
                  entityId: selectedEntityId,
                  phone: phoneCtrl.text.trim(),
                  oldBalance: entityType == 'General' ? 0.0 : oldBalance,
                  newBalance: calcNewBalance,
                  recordedBy: userName,
                  caisseName: selectedCaisse,
                  paymentMethod: selectedPaymentMethod,
                  createdAt: selectedDate.toIso8601String(),
                );

                if (mounted) {
                  Navigator.pop(context);
                  _loadData();
                }
              },
              label: Text(
                Localization.translate('حفظ', lang),
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                ),
              ),
              style: ElevatedButton.styleFrom(backgroundColor: Colors.teal),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settingsProvider = Provider.of<AppSettingsProvider>(context);
    final lang = settingsProvider.language;
    final currency = Localization.translate('د.ج', lang);
    final formatter = NumberFormat('#,##0.00');

    final bool isDark = Theme.of(context).brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate('الخزينة (Caisse)', lang),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: isDark
            ? Theme.of(context).appBarTheme.backgroundColor
            : Colors.teal,
        actions: [
          IconButton(
            icon: Icon(_showSearch ? Icons.search_off : Icons.search),
            tooltip: Localization.translate('بحث', lang),
            onPressed: () {
              setState(() {
                _showSearch = !_showSearch;
              });
            },
          ),
          IconButton(
            icon: Icon(_showFilters ? Icons.filter_alt_off : Icons.filter_alt),
            tooltip: Localization.translate('فلترة', lang),
            onPressed: () {
              setState(() {
                _showFilters = !_showFilters;
              });
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(
              builder: (context, viewport) => Column(
                children: [
                  // 1. شريط الصندوق المثبت في الأعلى
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: isDark
                          ? Colors.grey.shade900
                          : Colors.teal.shade50,
                      border: Border(
                        bottom: BorderSide(
                          color: isDark
                              ? Colors.grey.shade800
                              : Colors.teal.shade100,
                          width: 1,
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: DropdownButtonHideUnderline(
                            child: DropdownButton<String>(
                              value: _selectedCaisse,
                              isExpanded: true,
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                color: isDark ? Colors.tealAccent : Colors.teal,
                                fontSize: 13,
                                fontWeight: FontWeight.bold,
                              ),
                              items: [
                                DropdownMenuItem<String>(
                                  value: 'الكل',
                                  child: Text(
                                    Localization.translate(
                                      'الكل (جميع الصناديق)',
                                      lang,
                                    ),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                ),
                                ..._caisseNames.map(
                                  (name) => DropdownMenuItem<String>(
                                    value: name,
                                    child: Text(
                                      Localization.translate(name, lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                              onChanged: (val) {
                                setState(() {
                                  _selectedCaisse = val!;
                                  _loadData();
                                });
                              },
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            color: isDark
                                ? Colors.tealAccent.shade700
                                : Colors.teal,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            '${formatter.format(_totalBalance)} $currency',
                            style: TextStyle(
                              color: isDark ? Colors.black : Colors.white,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                          ),
                        ),
                        if (!widget.readOnly) ...[
                          const SizedBox(width: 6),
                          Tooltip(
                            message: Localization.translate(
                              'معاملة جديدة',
                              lang,
                            ),
                            child: InkWell(
                              onTap: _showAddTransactionDialog,
                              borderRadius: BorderRadius.circular(6),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: isDark
                                      ? Colors.tealAccent.shade700
                                      : Colors.teal.shade700,
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.add,
                                      size: 16,
                                      color: isDark
                                          ? Colors.black
                                          : Colors.white,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      Localization.translate(
                                        'معاملة جديدة',
                                        lang,
                                      ),
                                      style: TextStyle(
                                        color: isDark
                                            ? Colors.black
                                            : Colors.white,
                                        fontWeight: FontWeight.bold,
                                        fontFamily: 'Cairo',
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ],
                        const SizedBox(width: 4),
                        if (settingsProvider.canManageCaisses())
                          IconButton(
                            icon: Icon(
                              Icons.settings,
                              size: 20,
                              color: isDark ? Colors.tealAccent : Colors.teal,
                            ),
                            tooltip: Localization.translate(
                              'إدارة الصناديق',
                              lang,
                            ),
                            onPressed: _showManageCaissesDialog,
                          ),
                      ],
                    ),
                  ),

                  // 🟢 حقل البحث التفاعلي (يظهر ويختفي بناءً على الأيقونة في الأب بار)
                  if (_showSearch)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 8.0,
                      ),
                      child: TextField(
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'بحث بالاسم أو البيان',
                            lang,
                          ),
                          prefixIcon: const Icon(Icons.search),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                        onChanged: (val) {
                          setState(() {
                            _searchQuery = val;
                            _applyFilter();
                          });
                        },
                      ),
                    ),

                  // 🟢 خيارات الفلترة المتقدمة (تظهر وتختفي بناءً على الأيقونة في الأب بار)
                  if (_showFilters)
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12.0,
                          vertical: 4.0,
                        ),
                        child: Row(
                          children: [
                            SizedBox(
                              width: 175,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedTypeFilter,
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    'نوع المعاملة',
                                    lang,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(
                                      Localization.translate('الكل', lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'income',
                                    child: Text(
                                      Localization.translate('مقبوضات', lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'expense',
                                    child: Text(
                                      Localization.translate('مدفوعات', lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedTypeFilter = val!;
                                    _applyFilter();
                                  });
                                },
                              ),
                            ),
                            const SizedBox(width: 10),
                            SizedBox(
                              width: 175,
                              child: DropdownButtonFormField<String>(
                                isExpanded: true,
                                value: _selectedCategoryFilter,
                                decoration: InputDecoration(
                                  labelText: Localization.translate(
                                    'التصنيف',
                                    lang,
                                  ),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                ),
                                items: [
                                  DropdownMenuItem(
                                    value: 'all',
                                    child: Text(
                                      Localization.translate('كلها', lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                  DropdownMenuItem(
                                    value: 'general_expenses',
                                    child: Text(
                                      Localization.translate(
                                        'تكاليف إضافية / مصاريف عامة',
                                        lang,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                                onChanged: (val) {
                                  setState(() {
                                    _selectedCategoryFilter = val!;
                                    _applyFilter();
                                  });
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 🟢 كرت المجموع المصفى التلقائي (يظهر فقط عند التصفية أو البحث النشط)
                  if (_selectedTypeFilter != 'all' ||
                      _selectedCategoryFilter != 'all' ||
                      _searchQuery.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12.0,
                        vertical: 4.0,
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: isDark
                              ? Colors.teal.withValues(alpha: 0.15)
                              : Colors.teal.shade50,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: isDark
                                ? Colors.teal.shade800
                                : Colors.teal.shade100,
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              Localization.translate('إجمالي المصفى:', lang),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                color: isDark
                                    ? Colors.tealAccent
                                    : Colors.teal.shade900,
                              ),
                            ),
                            Column(
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                if (_filteredTotalIncome > 0)
                                  Text(
                                    '${Localization.translate('المقبوضات:', lang)} +${formatter.format(_filteredTotalIncome)} $currency',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: Colors.green,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                if (_filteredTotalExpense > 0)
                                  Text(
                                    '${Localization.translate('المدفوعات:', lang)} -${formatter.format(_filteredTotalExpense)} $currency',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                      color: Colors.red,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                Text(
                                  '${Localization.translate('الصافي:', lang)} ${formatter.format(_filteredTotalIncome - _filteredTotalExpense)} $currency',
                                  style: TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        (_filteredTotalIncome -
                                                _filteredTotalExpense) >=
                                            0
                                        ? Colors.green
                                        : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),

                  // 2. القائمة الرئيسية القابلة للتمرير بالكامل
                  Expanded(
                    child: viewport.maxWidth >= 900
                        ? widget._buildDesktopTreasuryTable(
                            context,
                            lang,
                            formatter,
                            currency,
                            isDark,
                            _filteredTransactions,
                            _filteredTotalIncome,
                            _filteredTotalExpense,
                            widget.readOnly,
                            settingsProvider.canEditPayments(),
                            settingsProvider.canDeletePayments(),
                            _desktopTableScrollController,
                            _showEditTransactionDialog,
                            _deleteTransaction,
                            (item) => _showReceiptOptions(context, item),
                            dateRange: _dateRange,
                            onDateRangeChanged: (range) {
                              setState(() {
                                _dateRange = range;
                                _applyFilter();
                              });
                            },
                            numericFilter: _numericFilter,
                            onNumericFilterChanged: (filter) {
                              setState(() {
                                _numericFilter = filter;
                                _applyFilter();
                              });
                            },
                            columnControllers: _treasuryColumnControllers,
                            columnNumericFilters: _treasuryNumericFilters,
                            onFiltersUpdated: () => setState(() => _applyFilter()),
                            onClearAllFilters: () {
                              setState(() {
                                for (final c in _treasuryColumnControllers.values) {
                                  c.clear();
                                }
                                _treasuryNumericFilters.clear();
                                _dateRange = const TableDateRange();
                                _numericFilter = const NumericFilterState();
                                _applyFilter();
                              });
                            },
                          )
                        : ListView.builder(
                            itemCount: _filteredTransactions.length + 1,
                            // +1 for big balance card
                            itemBuilder: (context, index) {
                              if (index == 0) {
                                return Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(20),
                                  decoration: BoxDecoration(
                                    gradient: LinearGradient(
                                      colors: isDark
                                          ? [
                                              Colors.teal.shade900,
                                              Colors.grey.shade900,
                                            ]
                                          : [Colors.teal, Colors.green],
                                    ),
                                  ),
                                  child: Column(
                                    children: [
                                      Text(
                                        Localization.translate(
                                          'رصيد الصندوق',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 16,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${formatter.format(_totalBalance)} $currency',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 32,
                                          fontWeight: FontWeight.bold,
                                          fontFamily: 'Cairo',
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              }

                              final item = _filteredTransactions[index - 1];
                              final tType =
                                  item['transaction_type']?.toString() ?? '';
                              final isIncome =
                                  tType == 'Encaissement' ||
                                  tType == 'income' ||
                                  (!tType.contains('Achat') &&
                                      !tType.contains('Purchase') &&
                                      !tType.contains('Décaissement') &&
                                      !tType.contains('expense'));

                              String dateStr = item['created_at'] ?? '';
                              if (dateStr.length > 16) {
                                dateStr = dateStr
                                    .substring(0, 16)
                                    .replaceFirst('T', ' ');
                              }

                              final oldBal = (item['old_balance'] as num?)
                                  ?.toDouble();
                              final newBal = (item['new_balance'] as num?)
                                  ?.toDouble();
                              final phone = item['phone']?.toString() ?? '';

                              return Card(
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 6,
                                ),
                                elevation: 2,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(12),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      // Row 1: Icon and Title
                                      Row(
                                        children: [
                                          CircleAvatar(
                                            radius: 16,
                                            backgroundColor: isIncome
                                                ? Colors.green.withValues(
                                                    alpha: 0.15,
                                                  )
                                                : Colors.red.withValues(
                                                    alpha: 0.15,
                                                  ),
                                            child: Icon(
                                              isIncome
                                                  ? Icons.arrow_downward
                                                  : Icons.arrow_upward,
                                              color: isIncome
                                                  ? Colors.green
                                                  : Colors.red,
                                              size: 16,
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: _highlightText(
                                              _buildTransactionTitle(
                                                item,
                                                lang,
                                              ),
                                              _searchQuery,
                                              TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontFamily: 'Cairo',
                                                fontSize: 13,
                                                color: isDark
                                                    ? Colors.white
                                                    : Colors.black87,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),

                                      // Row 2: Paid Amount in its own row
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.spaceBetween,
                                        children: [
                                          Text(
                                            '${Localization.translate('المبلغ:', lang)} / Montant:',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.grey,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                          Text(
                                            '${isIncome ? "+" : "-"}${formatter.format((item['amount'] as num?)?.toDouble() ?? 0)} $currency',
                                            style: TextStyle(
                                              color: isIncome
                                                  ? Colors.green
                                                  : Colors.red,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 15,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      if (phone.isNotEmpty) ...[
                                        Row(
                                          children: [
                                            const Text(
                                              '📞 ',
                                              style: TextStyle(fontSize: 11),
                                            ),
                                            Expanded(
                                              child: _highlightText(
                                                phone,
                                                _searchQuery,
                                                const TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.blueGrey,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 4),
                                      ],

                                      if (oldBal != null &&
                                          newBal != null &&
                                          item['entity_type'] != 'General') ...[
                                        Padding(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 2,
                                          ),
                                          child: Text(
                                            '${Localization.translate("الرصيد", lang)}: ${formatter.format(oldBal.abs())} → ${formatter.format(newBal.abs())} $currency',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.grey.shade600,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                      ],

                                      // Row 3: Metadata
                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        crossAxisAlignment:
                                            WrapCrossAlignment.center,
                                        children: [
                                          Text(
                                            '${Localization.translate('بواسطة', lang)}: ${item['recorded_by'] ?? ''} | $dateStr',
                                            style: TextStyle(
                                              fontSize: 11,
                                              color: isDark
                                                  ? Colors.white60
                                                  : Colors.black54,
                                              fontFamily: 'Cairo',
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),

                                      Wrap(
                                        spacing: 8,
                                        runSpacing: 4,
                                        children: [
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.teal.withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.inbox,
                                                  size: 10,
                                                  color: Colors.teal,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  t(
                                                    item['caisse_name']
                                                            ?.toString() ??
                                                        'الصندوق الرئيسي',
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isDark
                                                        ? Colors.tealAccent
                                                        : Colors.teal,
                                                    fontWeight: FontWeight.bold,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(
                                              horizontal: 6,
                                              vertical: 2,
                                            ),
                                            decoration: BoxDecoration(
                                              color: Colors.blue.withValues(
                                                alpha: 0.08,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                const Icon(
                                                  Icons.payment,
                                                  size: 10,
                                                  color: Colors.blue,
                                                ),
                                                const SizedBox(width: 3),
                                                Text(
                                                  t(
                                                    item['payment_method']
                                                            ?.toString() ??
                                                        'نقداً / Espèce',
                                                  ),
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: isDark
                                                        ? Colors.blueAccent
                                                        : Colors.blue,
                                                    fontFamily: 'Cairo',
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                      const Divider(height: 16),

                                      // Row 4: Action Print options button in its own row
                                      Row(
                                        mainAxisAlignment:
                                            MainAxisAlignment.end,
                                        children: [
                                          TextButton.icon(
                                            style: TextButton.styleFrom(
                                              foregroundColor: isDark
                                                  ? Colors.tealAccent
                                                  : Colors.teal,
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                    horizontal: 12,
                                                    vertical: 4,
                                                  ),
                                              minimumSize: Size.zero,
                                              tapTargetSize:
                                                  MaterialTapTargetSize
                                                      .shrinkWrap,
                                              shape: RoundedRectangleBorder(
                                                borderRadius:
                                                    BorderRadius.circular(6),
                                                side: BorderSide(
                                                  color: isDark
                                                      ? Colors.tealAccent
                                                      : Colors.teal,
                                                ),
                                              ),
                                            ),
                                            icon: const Icon(
                                              Icons.print,
                                              size: 14,
                                            ),
                                            label: Text(
                                              Localization.translate(
                                                'خيارات الوصل',
                                                lang,
                                              ),
                                              style: const TextStyle(
                                                fontFamily: 'Cairo',
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            onPressed: () =>
                                                _showReceiptOptions(
                                                  context,
                                                  item,
                                                ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
    );
  }

  String _buildTransactionTitle(Map<String, dynamic> item, AppLanguage lang) {
    final desc = item['description']?.toString() ?? '';
    if (desc.startsWith('دفعة لطلبية رقم ')) {
      final orderId = desc.replaceFirst('دفعة لطلبية رقم ', '');
      return '${Localization.translate('دفعة لطلبية', lang)} ${Localization.translate('رقم', lang)} $orderId';
    }
    if (desc.startsWith('من الزبون: ')) {
      return '${Localization.translate('من الزبون', lang)}: ${desc.replaceFirst('من الزبون: ', '')}';
    }
    if (desc.startsWith('للمورد: ')) {
      return '${Localization.translate('للمورد', lang)}: ${desc.replaceFirst('للمورد: ', '')}';
    }
    if (desc.startsWith('استرجاع من المورد: ')) {
      return '${Localization.translate('استرجاع من المورد', lang)}: ${desc.replaceFirst('استرجاع من المورد: ', '')}';
    }
    if (desc.startsWith('إلى العامل: ')) {
      return '${Localization.translate('إلى العامل', lang)}: ${desc.replaceFirst('إلى العامل: ', '')}';
    }
    if (desc.startsWith('دفع للمورد الفاتورة')) {
      return desc.replaceFirst(
        'دفع للمورد الفاتورة',
        Localization.translate('دفع للمورد الفاتورة', lang),
      );
    }
    if (desc.startsWith('دفع للمورد الفاتوره')) {
      return desc.replaceFirst(
        'دفع للمورد الفاتوره',
        Localization.translate('دفع للمورد الفاتورة', lang),
      );
    }
    if (desc.startsWith('دفع للمورد: ')) {
      final content = desc.replaceFirst('دفع للمورد: ', '');
      if (content.contains(' - الفاتورة: ')) {
        final parts = content.split(' - الفاتورة: ');
        final supplier = parts[0];
        final inv = parts[1];
        return '${Localization.translate('دفع للمورد:', lang)} $supplier - ${Localization.translate('رقم الفاتورة', lang)}: $inv';
      }
      return '${Localization.translate('دفع للمورد:', lang)} $content';
    }
    if (desc.startsWith('دفع للمورد:')) {
      return desc.replaceFirst(
        'دفع للمورد:',
        '${Localization.translate('دفع للمورد:', lang)}',
      );
    }
    if (desc.startsWith('دفع للمورد فاتورة رقم')) {
      return desc.replaceFirst(
        'دفع للمورد فاتورة رقم',
        Localization.translate('دفع للمورد فاتورة رقم', lang),
      );
    }
    return desc.isEmpty ? Localization.translate('بدون بيان', lang) : desc;
  }

  String t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }
}
