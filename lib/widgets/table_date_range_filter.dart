import 'package:flutter/material.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

enum DateRangePreset {
  all,
  today,
  thisWeek,
  thisMonth,
  lastThreeMonths,
  custom,
}

class TableDateRange {
  final DateTime? startDate;
  final DateTime? endDate;
  final DateRangePreset preset;

  const TableDateRange({
    this.startDate,
    this.endDate,
    this.preset = DateRangePreset.all,
  });

  bool get isActive => preset != DateRangePreset.all || startDate != null || endDate != null;

  /// Determines if a date falls within the selected start and end dates (inclusive of whole days)
  bool isWithinRange(DateTime? date) {
    if (date == null) return false;
    if (!isActive) return true;

    if (startDate != null) {
      final startOfDay = DateTime(startDate!.year, startDate!.month, startDate!.day);
      if (date.isBefore(startOfDay)) return false;
    }

    if (endDate != null) {
      final endOfDay = DateTime(endDate!.year, endDate!.month, endDate!.day, 23, 59, 59, 999);
      if (date.isAfter(endOfDay)) return false;
    }

    return true;
  }

  static TableDateRange fromPreset(DateRangePreset preset) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    switch (preset) {
      case DateRangePreset.all:
        return const TableDateRange(preset: DateRangePreset.all);

      case DateRangePreset.today:
        return TableDateRange(
          startDate: today,
          endDate: today,
          preset: DateRangePreset.today,
        );

      case DateRangePreset.thisWeek:
        // Week starts on Saturday (Algeria/Arab world standard) or Monday
        final weekday = now.weekday; // 1 = Mon, 6 = Sat, 7 = Sun
        final daysFromSaturday = (weekday == 7) ? 1 : ((weekday == 6) ? 0 : weekday + 1);
        final startOfWeek = today.subtract(Duration(days: daysFromSaturday));
        return TableDateRange(
          startDate: startOfWeek,
          endDate: today,
          preset: DateRangePreset.thisWeek,
        );

      case DateRangePreset.thisMonth:
        final startOfMonth = DateTime(now.year, now.month, 1);
        return TableDateRange(
          startDate: startOfMonth,
          endDate: today,
          preset: DateRangePreset.thisMonth,
        );

      case DateRangePreset.lastThreeMonths:
        final start = DateTime(now.year, now.month - 3, now.day);
        return TableDateRange(
          startDate: start,
          endDate: today,
          preset: DateRangePreset.lastThreeMonths,
        );

      case DateRangePreset.custom:
        return TableDateRange(
          startDate: today.subtract(const Duration(days: 30)),
          endDate: today,
          preset: DateRangePreset.custom,
        );
    }
  }
}

class TableDateRangeFilterBar extends StatefulWidget {
  final TableDateRange initialRange;
  final ValueChanged<TableDateRange> onRangeChanged;
  final AppLanguage lang;
  final bool compact;

  const TableDateRangeFilterBar({
    super.key,
    this.initialRange = const TableDateRange(),
    required this.onRangeChanged,
    this.lang = AppLanguage.arabic,
    this.compact = false,
  });

  @override
  State<TableDateRangeFilterBar> createState() => _TableDateRangeFilterBarState();
}

class _TableDateRangeFilterBarState extends State<TableDateRangeFilterBar> {
  late TableDateRange _currentRange;

  @override
  void initState() {
    super.initState();
    _currentRange = widget.initialRange;
  }

  void _applyPreset(DateRangePreset preset) {
    setState(() {
      _currentRange = TableDateRange.fromPreset(preset);
    });
    widget.onRangeChanged(_currentRange);
  }

  Future<void> _pickStartDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentRange.startDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _currentRange = TableDateRange(
          startDate: picked,
          endDate: _currentRange.endDate,
          preset: DateRangePreset.custom,
        );
      });
      widget.onRangeChanged(_currentRange);
    }
  }

  Future<void> _pickEndDate(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _currentRange.endDate ?? now,
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
    );
    if (picked != null) {
      setState(() {
        _currentRange = TableDateRange(
          startDate: _currentRange.startDate,
          endDate: picked,
          preset: DateRangePreset.custom,
        );
      });
      widget.onRangeChanged(_currentRange);
    }
  }

  void _reset() {
    _applyPreset(DateRangePreset.all);
  }

  String _formatDate(DateTime? date) {
    if (date == null) return '--/--/----';
    final y = date.year.toString().padLeft(4, '0');
    final m = date.month.toString().padLeft(2, '0');
    final d = date.day.toString().padLeft(2, '0');
    return '$y/$m/$d';
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final lang = widget.lang;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: widget.compact ? 8 : 12,
        vertical: widget.compact ? 6 : 8,
      ),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _currentRange.isActive
              ? const Color(0xFF2563EB).withValues(alpha: 0.4)
              : (isDark ? Colors.white12 : Colors.grey.shade200),
        ),
      ),
      child: Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        alignment: WrapAlignment.start,
        spacing: 8,
        runSpacing: 8,
        children: [
          // Icon and Label
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.date_range_rounded,
                size: 18,
                color: _currentRange.isActive ? const Color(0xFF2563EB) : Colors.grey,
              ),
              const SizedBox(width: 6),
              Text(
                Localization.translate('فلترة التاريخ:', lang),
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.bold,
                  color: isDark ? Colors.white : const Color(0xFF0F172A),
                ),
              ),
            ],
          ),

          // Presets (All, Today, Week, Month, 3 Months)
          _buildPresetChip(DateRangePreset.all, Localization.translate('الكل', lang), isDark),
          _buildPresetChip(DateRangePreset.today, Localization.translate('اليوم', lang), isDark),
          _buildPresetChip(DateRangePreset.thisWeek, Localization.translate('هذا الأسبوع', lang), isDark),
          _buildPresetChip(DateRangePreset.thisMonth, Localization.translate('هذا الشهر', lang), isDark),
          _buildPresetChip(DateRangePreset.lastThreeMonths, Localization.translate('آخر 3 أشهر', lang), isDark),

          // "From" Date Selector
          InkWell(
            onTap: () => _pickStartDate(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentRange.startDate != null
                      ? const Color(0xFF2563EB).withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${Localization.translate("من:", lang)} ',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                  Text(
                    _formatDate(_currentRange.startDate),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.event, size: 14, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ),

          // "To" Date Selector
          InkWell(
            onTap: () => _pickEndDate(context),
            borderRadius: BorderRadius.circular(8),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: _currentRange.endDate != null
                      ? const Color(0xFF2563EB).withValues(alpha: 0.5)
                      : Colors.transparent,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${Localization.translate("إلى:", lang)} ',
                    style: TextStyle(fontSize: 11, color: isDark ? Colors.grey.shade400 : Colors.grey.shade600),
                  ),
                  Text(
                    _formatDate(_currentRange.endDate),
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                  const SizedBox(width: 4),
                  const Icon(Icons.event, size: 14, color: Color(0xFF2563EB)),
                ],
              ),
            ),
          ),

          // Reset button
          if (_currentRange.isActive)
            IconButton(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: Localization.translate('مسح فلتر التاريخ', lang),
              onPressed: _reset,
              visualDensity: VisualDensity.compact,
            ),
        ],
      ),
    );
  }

  Widget _buildPresetChip(DateRangePreset preset, String label, bool isDark) {
    final isSelected = _currentRange.preset == preset;
    return InkWell(
      onTap: () => _applyPreset(preset),
      borderRadius: BorderRadius.circular(20),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: isSelected
              ? const Color(0xFF2563EB)
              : (isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9)),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
            color: isSelected ? Colors.white : (isDark ? Colors.grey.shade300 : Colors.grey.shade700),
          ),
        ),
      ),
    );
  }
}
