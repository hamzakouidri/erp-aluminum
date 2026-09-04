import 'package:flutter/material.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

/// Supported mathematical comparison operators
enum NumericFilterOperator {
  none,
  equalsZero, // = 0
  notEqualsZero, // != 0
  greaterThanZero, // > 0
  lessThanZero, // < 0
  greaterThanOrEqualZero, // >= 0
  lessThanOrEqualZero, // <= 0
  equalsValue, // = X
  greaterThanValue, // > X
  lessThanValue, // < X
  greaterThanOrEqualValue, // >= X
  lessThanOrEqualValue, // <= X
  notEqualsValue, // != X
}

/// Represents the active state of a numeric search/filter
class NumericFilterState {
  final NumericFilterOperator operator;
  final double? targetValue;
  final String rawQuery;

  const NumericFilterState({
    this.operator = NumericFilterOperator.none,
    this.targetValue,
    this.rawQuery = '',
  });

  bool get isActive =>
      operator != NumericFilterOperator.none ||
      (targetValue != null) ||
      rawQuery.trim().isNotEmpty;

  /// Evaluates whether a given number matches this filter criteria
  bool matches(num? value) {
    if (value == null) return false;
    final v = value.toDouble();

    switch (operator) {
      case NumericFilterOperator.none:
        if (targetValue != null) {
          return (v - targetValue!).abs() < 0.0001 ||
              v.toString().contains(rawQuery.trim());
        }
        return true;

      case NumericFilterOperator.equalsZero:
        return v.abs() < 0.0001;

      case NumericFilterOperator.notEqualsZero:
        return v.abs() >= 0.0001;

      case NumericFilterOperator.greaterThanZero:
        return v > 0.0001;

      case NumericFilterOperator.lessThanZero:
        return v < -0.0001;

      case NumericFilterOperator.greaterThanOrEqualZero:
        return v >= -0.0001;

      case NumericFilterOperator.lessThanOrEqualZero:
        return v <= 0.0001;

      case NumericFilterOperator.equalsValue:
        final target = targetValue ?? 0.0;
        return (v - target).abs() < 0.0001;

      case NumericFilterOperator.greaterThanValue:
        final target = targetValue ?? 0.0;
        return v > target;

      case NumericFilterOperator.lessThanValue:
        final target = targetValue ?? 0.0;
        return v < target;

      case NumericFilterOperator.greaterThanOrEqualValue:
        final target = targetValue ?? 0.0;
        return v >= target - 0.0001;

      case NumericFilterOperator.lessThanOrEqualValue:
        final target = targetValue ?? 0.0;
        return v <= target + 0.0001;

      case NumericFilterOperator.notEqualsValue:
        final target = targetValue ?? 0.0;
        return (v - target).abs() >= 0.0001;
    }
  }

  String getDisplaySymbol() {
    switch (operator) {
      case NumericFilterOperator.equalsZero:
        return '= 0';
      case NumericFilterOperator.notEqualsZero:
        return '≠ 0';
      case NumericFilterOperator.greaterThanZero:
        return '> 0';
      case NumericFilterOperator.lessThanZero:
        return '< 0';
      case NumericFilterOperator.greaterThanOrEqualZero:
        return '≥ 0';
      case NumericFilterOperator.lessThanOrEqualZero:
        return '≤ 0';
      case NumericFilterOperator.equalsValue:
        return '= ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.greaterThanValue:
        return '> ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.lessThanValue:
        return '< ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.greaterThanOrEqualValue:
        return '≥ ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.lessThanOrEqualValue:
        return '≤ ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.notEqualsValue:
        return '≠ ${targetValue?.toStringAsFixed(targetValue! % 1 == 0 ? 0 : 2) ?? 'X'}';
      case NumericFilterOperator.none:
        return '';
    }
  }

  String getLabel(AppLanguage lang) {
    final symbol = getDisplaySymbol();
    String label(String key) => Localization.translate(key, lang)
        .replaceAll('{symbol}', symbol);

    switch (operator) {
      case NumericFilterOperator.none:
        return label('الكل (بدون فلتر)');
      case NumericFilterOperator.equalsZero:
        return label('يساوي الصفر ({symbol})');
      case NumericFilterOperator.notEqualsZero:
        return label('لا يساوي الصفر ({symbol})');
      case NumericFilterOperator.greaterThanZero:
        return label('أكبر تماماً من الصفر ({symbol})');
      case NumericFilterOperator.lessThanZero:
        return label('أصغر تماماً من الصفر ({symbol})');
      case NumericFilterOperator.greaterThanOrEqualZero:
        return label('أكبر أو يساوي الصفر ({symbol})');
      case NumericFilterOperator.lessThanOrEqualZero:
        return label('أصغر أو يساوي الصفر ({symbol})');
      case NumericFilterOperator.equalsValue:
        return label('يساوي القيمة ({symbol})');
      case NumericFilterOperator.greaterThanValue:
        return label('أكبر من القيمة ({symbol})');
      case NumericFilterOperator.lessThanValue:
        return label('أصغر من القيمة ({symbol})');
      case NumericFilterOperator.greaterThanOrEqualValue:
        return label('أكبر أو يساوي القيمة ({symbol})');
      case NumericFilterOperator.lessThanOrEqualValue:
        return label('أصغر أو يساوي القيمة ({symbol})');
      case NumericFilterOperator.notEqualsValue:
        return label('لا يساوي القيمة ({symbol})');
    }
  }
}

/// A search input field equipped with a dropdown icon for mathematical filtering
class NumericFilterSearchField extends StatefulWidget {
  final String hintText;
  final ValueChanged<NumericFilterState> onFilterChanged;
  final AppLanguage lang;
  final double? width;
  final NumericFilterState initialState;

  const NumericFilterSearchField({
    super.key,
    required this.hintText,
    required this.onFilterChanged,
    this.lang = AppLanguage.arabic,
    this.width,
    this.initialState = const NumericFilterState(),
  });

  @override
  State<NumericFilterSearchField> createState() =>
      _NumericFilterSearchFieldState();
}

class _NumericFilterSearchFieldState extends State<NumericFilterSearchField> {
  late final TextEditingController _controller;
  late NumericFilterOperator _currentOperator;

  @override
  void initState() {
    super.initState();
    _currentOperator = widget.initialState.operator;
    _controller = TextEditingController(text: widget.initialState.rawQuery);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _notify() {
    final raw = _controller.text.trim();
    final parsed = double.tryParse(raw.replaceAll(',', '.'));
    final state = NumericFilterState(
      operator: _currentOperator,
      targetValue: parsed,
      rawQuery: raw,
    );
    widget.onFilterChanged(state);
  }

  void _setOperator(NumericFilterOperator op) {
    setState(() {
      _currentOperator = op;
    });
    _notify();
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _currentOperator = NumericFilterOperator.none;
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final raw = _controller.text.trim();
    final hasNumber = double.tryParse(raw.replaceAll(',', '.')) != null;
    final isActive =
        _currentOperator != NumericFilterOperator.none || raw.isNotEmpty;

    final symbol = NumericFilterState(
      operator: _currentOperator,
      targetValue: double.tryParse(raw.replaceAll(',', '.')),
    ).getDisplaySymbol();

    return SizedBox(
      width: widget.width ?? 280,
      height: 42,
      child: TextField(
        controller: _controller,
        onChanged: (_) => _notify(),
        style: TextStyle(
          fontSize: 13,
          color: isDark ? Colors.white : const Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: TextStyle(
            fontSize: 12,
            color: isDark ? Colors.grey.shade400 : Colors.grey.shade500,
          ),
          filled: true,
          fillColor: isDark ? const Color(0xFF1E293B) : Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 0,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isActive
                  ? (isDark ? Colors.blueAccent : const Color(0xFF2563EB))
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
            ),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: BorderSide(
              color: isActive
                  ? (isDark ? Colors.blueAccent : const Color(0xFF2563EB))
                  : (isDark ? Colors.white12 : Colors.grey.shade300),
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF2563EB), width: 1.8),
          ),
          prefixIcon: PopupMenuButton<NumericFilterOperator>(
            tooltip: Localization.translate(
              'خيارات الفلترة الرقمية',
              widget.lang,
            ),
            icon: Container(
              padding: const EdgeInsets.all(4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.filter_alt_rounded,
                    size: 18,
                    color: _currentOperator != NumericFilterOperator.none
                        ? const Color(0xFF2563EB)
                        : (isDark
                              ? Colors.grey.shade400
                              : Colors.grey.shade600),
                  ),
                  if (symbol.isNotEmpty) ...[
                    const SizedBox(width: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 1.5,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2563EB).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      ),
                    ),
                  ],
                  Icon(
                    Icons.arrow_drop_down_rounded,
                    size: 16,
                    color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                  ),
                ],
              ),
            ),
            onSelected: _setOperator,
            itemBuilder: (context) {
              return [
                // 1. None
                _buildMenuItem(
                  NumericFilterOperator.none,
                  Icons.clear_all_rounded,
                  Colors.grey,
                ),
                const PopupMenuDivider(),

                // 2. Zero comparisons
                _buildMenuItem(
                  NumericFilterOperator.equalsZero,
                  Icons.exposure_zero_rounded,
                  Colors.blue,
                ),
                _buildMenuItem(
                  NumericFilterOperator.notEqualsZero,
                  Icons.remove_circle_outline_rounded,
                  Colors.orange,
                ),
                _buildMenuItem(
                  NumericFilterOperator.greaterThanZero,
                  Icons.trending_up_rounded,
                  Colors.green,
                ),
                _buildMenuItem(
                  NumericFilterOperator.lessThanZero,
                  Icons.trending_down_rounded,
                  Colors.red,
                ),
                _buildMenuItem(
                  NumericFilterOperator.greaterThanOrEqualZero,
                  Icons.keyboard_double_arrow_up_rounded,
                  Colors.teal,
                ),
                _buildMenuItem(
                  NumericFilterOperator.lessThanOrEqualZero,
                  Icons.keyboard_double_arrow_down_rounded,
                  Colors.deepOrange,
                ),

                // 3. Specific value comparisons (available or highlighted if a number is typed)
                if (hasNumber) ...[
                  const PopupMenuDivider(),
                  _buildMenuItem(
                    NumericFilterOperator.equalsValue,
                    Icons.check_rounded,
                    Colors.blue,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.greaterThanValue,
                    Icons.arrow_upward_rounded,
                    Colors.green,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.lessThanValue,
                    Icons.arrow_downward_rounded,
                    Colors.red,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.greaterThanOrEqualValue,
                    Icons.north_east_rounded,
                    Colors.teal,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.lessThanOrEqualValue,
                    Icons.south_east_rounded,
                    Colors.deepOrange,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.notEqualsValue,
                    Icons.close_rounded,
                    Colors.purple,
                  ),
                ],
              ];
            },
          ),
          suffixIcon: isActive
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: _clear,
                  tooltip: Localization.translate('مسح الفلتر', widget.lang),
                )
              : null,
        ),
      ),
    );
  }

  PopupMenuItem<NumericFilterOperator> _buildMenuItem(
    NumericFilterOperator op,
    IconData icon,
    Color color,
  ) {
    final state = NumericFilterState(
      operator: op,
      targetValue: double.tryParse(
        _controller.text.trim().replaceAll(',', '.'),
      ),
    );
    final isSelected = _currentOperator == op;

    return PopupMenuItem<NumericFilterOperator>(
      value: op,
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              state.getLabel(widget.lang),
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF2563EB) : null,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF2563EB),
              size: 16,
            ),
        ],
      ),
    );
  }
}

/// A compact per-column filter field designed specifically for the table filter sub-row
class CompactTableFilterField extends StatefulWidget {
  final String hintText;
  final bool isNumeric;
  final TextEditingController? controller;
  final ValueChanged<String>? onTextChanged;
  final ValueChanged<NumericFilterState>? onNumericFilterChanged;
  final List<TableFilterOption> options;
  final String? optionsTooltip;
  final AppLanguage lang;
  final NumericFilterState initialNumericState;

  const CompactTableFilterField({
    super.key,
    required this.hintText,
    this.isNumeric = false,
    this.controller,
    this.onTextChanged,
    this.onNumericFilterChanged,
    this.options = const [],
    this.optionsTooltip,
    this.lang = AppLanguage.arabic,
    this.initialNumericState = const NumericFilterState(),
  });

  @override
  State<CompactTableFilterField> createState() =>
      _CompactTableFilterFieldState();
}

class _CompactTableFilterFieldState extends State<CompactTableFilterField> {
  late final TextEditingController _controller;
  late NumericFilterOperator _currentOperator;

  @override
  void initState() {
    super.initState();
    _currentOperator = widget.initialNumericState.operator;
    _controller =
        widget.controller ??
        TextEditingController(text: widget.initialNumericState.rawQuery);
  }

  @override
  void dispose() {
    if (widget.controller == null) {
      _controller.dispose();
    }
    super.dispose();
  }

  void _notify() {
    final raw = _controller.text.trim();
    if (widget.isNumeric) {
      final parsed = double.tryParse(raw.replaceAll(',', '.'));
      final state = NumericFilterState(
        operator: _currentOperator,
        targetValue: parsed,
        rawQuery: raw,
      );
      widget.onNumericFilterChanged?.call(state);
    } else {
      widget.onTextChanged?.call(raw);
    }
  }

  void _setOperator(NumericFilterOperator op) {
    setState(() {
      _currentOperator = op;
    });
    _notify();
  }

  void _clear() {
    setState(() {
      _controller.clear();
      _currentOperator = NumericFilterOperator.none;
    });
    _notify();
  }

  void _selectOption(TableFilterOption option) {
    setState(() {
      // Keep the field readable in the current language while the filter
      // logic still accepts both the translated label and the raw value.
      _controller.text = option.value.isEmpty ? '' : option.label;
      _controller.selection = TextSelection.collapsed(
        offset: _controller.text.length,
      );
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final raw = _controller.text.trim();
    final hasNumber = double.tryParse(raw.replaceAll(',', '.')) != null;
    final isActive =
        (widget.isNumeric && _currentOperator != NumericFilterOperator.none) ||
        raw.isNotEmpty;

    final symbol = widget.isNumeric
        ? NumericFilterState(
            operator: _currentOperator,
            targetValue: double.tryParse(raw.replaceAll(',', '.')),
          ).getDisplaySymbol()
        : '';

    return Container(
      height: 28,
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isActive
              ? (isDark ? Colors.blueAccent : const Color(0xFF2563EB))
              : (isDark ? Colors.white12 : Colors.grey.shade300),
          width: isActive ? 1.2 : 0.8,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          if (widget.options.isNotEmpty)
            PopupMenuButton<TableFilterOption>(
              tooltip:
                  widget.optionsTooltip ??
                  Localization.translate('اختيار من القائمة', widget.lang),
              padding: EdgeInsets.zero,
              icon: Icon(
                Icons.filter_list_rounded,
                size: 13,
                color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
              ),
              onSelected: _selectOption,
              itemBuilder: (context) => widget.options
                  .map(
                    (option) => PopupMenuItem<TableFilterOption>(
                      value: option,
                      child: Row(
                        children: [
                          Icon(
                            option.icon ?? Icons.label_outline_rounded,
                            size: 16,
                            color:
                                option.color ??
                                (isDark
                                    ? Colors.grey.shade300
                                    : Colors.blueGrey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              option.label,
                              style: const TextStyle(
                                fontSize: 11.5,
                                fontFamily: 'Cairo',
                              ),
                            ),
                          ),
                          if (_controller.text.trim() == option.value ||
                              _controller.text.trim() == option.label)
                            const Icon(
                              Icons.check_circle_rounded,
                              color: Color(0xFF2563EB),
                              size: 15,
                            ),
                        ],
                      ),
                    ),
                  )
                  .toList(),
            ),

          // Operator dropdown for numeric fields
          if (widget.isNumeric)
            PopupMenuButton<NumericFilterOperator>(
              tooltip: Localization.translate(
                'خيارات الفلترة الرقمية',
                widget.lang,
              ),
              padding: EdgeInsets.zero,
              icon: Container(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (symbol.isNotEmpty)
                      Text(
                        symbol,
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF2563EB),
                        ),
                      )
                    else
                      Icon(
                        Icons.filter_list_rounded,
                        size: 13,
                        color: isDark
                            ? Colors.grey.shade400
                            : Colors.grey.shade600,
                      ),
                    Icon(
                      Icons.arrow_drop_down,
                      size: 12,
                      color: isDark
                          ? Colors.grey.shade400
                          : Colors.grey.shade600,
                    ),
                  ],
                ),
              ),
              onSelected: _setOperator,
              itemBuilder: (context) {
                return [
                  _buildMenuItem(
                    NumericFilterOperator.none,
                    Icons.clear_all_rounded,
                    Colors.grey,
                  ),
                  const PopupMenuDivider(),
                  _buildMenuItem(
                    NumericFilterOperator.equalsZero,
                    Icons.exposure_zero_rounded,
                    Colors.blue,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.notEqualsZero,
                    Icons.remove_circle_outline_rounded,
                    Colors.orange,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.greaterThanZero,
                    Icons.trending_up_rounded,
                    Colors.green,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.lessThanZero,
                    Icons.trending_down_rounded,
                    Colors.red,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.greaterThanOrEqualZero,
                    Icons.keyboard_double_arrow_up_rounded,
                    Colors.teal,
                  ),
                  _buildMenuItem(
                    NumericFilterOperator.lessThanOrEqualZero,
                    Icons.keyboard_double_arrow_down_rounded,
                    Colors.deepOrange,
                  ),
                  if (hasNumber) ...[
                    const PopupMenuDivider(),
                    _buildMenuItem(
                      NumericFilterOperator.equalsValue,
                      Icons.check_rounded,
                      Colors.blue,
                    ),
                    _buildMenuItem(
                      NumericFilterOperator.greaterThanValue,
                      Icons.arrow_upward_rounded,
                      Colors.green,
                    ),
                    _buildMenuItem(
                      NumericFilterOperator.lessThanValue,
                      Icons.arrow_downward_rounded,
                      Colors.red,
                    ),
                    _buildMenuItem(
                      NumericFilterOperator.greaterThanOrEqualValue,
                      Icons.north_east_rounded,
                      Colors.teal,
                    ),
                    _buildMenuItem(
                      NumericFilterOperator.lessThanOrEqualValue,
                      Icons.south_east_rounded,
                      Colors.deepOrange,
                    ),
                    _buildMenuItem(
                      NumericFilterOperator.notEqualsValue,
                      Icons.close_rounded,
                      Colors.purple,
                    ),
                  ],
                ];
              },
            ),

          // Text Field
          Expanded(
            child: TextField(
              controller: _controller,
              onChanged: (_) => _notify(),
              style: TextStyle(
                fontSize: 11,
                fontFamily: 'Cairo',
                color: isDark ? Colors.white : const Color(0xFF0F172A),
              ),
              decoration: InputDecoration(
                hintText: widget.hintText,
                hintStyle: TextStyle(
                  fontSize: 10,
                  fontFamily: 'Cairo',
                  color: isDark ? Colors.grey.shade500 : Colors.grey.shade400,
                ),
                isDense: true,
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 4,
                  vertical: 4,
                ),
                border: InputBorder.none,
                enabledBorder: InputBorder.none,
                focusedBorder: InputBorder.none,
              ),
            ),
          ),

          // Clear button
          if (isActive)
            InkWell(
              onTap: _clear,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 3),
                child: Icon(
                  Icons.close_rounded,
                  size: 13,
                  color: isDark ? Colors.grey.shade400 : Colors.grey.shade600,
                ),
              ),
            ),
        ],
      ),
    );
  }

  PopupMenuItem<NumericFilterOperator> _buildMenuItem(
    NumericFilterOperator op,
    IconData icon,
    Color color,
  ) {
    final state = NumericFilterState(
      operator: op,
      targetValue: double.tryParse(
        _controller.text.trim().replaceAll(',', '.'),
      ),
    );
    final isSelected = _currentOperator == op;

    return PopupMenuItem<NumericFilterOperator>(
      value: op,
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              state.getLabel(widget.lang),
              style: TextStyle(
                fontSize: 11.5,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? const Color(0xFF2563EB) : null,
              ),
            ),
          ),
          if (isSelected)
            const Icon(
              Icons.check_circle_rounded,
              color: Color(0xFF2563EB),
              size: 15,
            ),
        ],
      ),
    );
  }
}

/// An optional predefined choice displayed inside a compact table filter.
/// `value` is what is written to the field and used by the filter; `label` is
/// what the user sees in the menu.
class TableFilterOption {
  final String value;
  final String label;
  final IconData? icon;
  final Color? color;

  const TableFilterOption({
    required this.value,
    required this.label,
    this.icon,
    this.color,
  });
}
