import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/widgets/numeric_filter_search_field.dart';
import 'package:database_data/widgets/table_date_range_filter.dart';
import 'package:database_data/settings/app_settings.dart';

void main() {
  group('NumericFilterState Tests', () {
    test('Equals zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.equalsZero);
      expect(filter.matches(0), isTrue);
      expect(filter.matches(0.0), isTrue);
      expect(filter.matches(0.00001), isTrue);
      expect(filter.matches(5), isFalse);
      expect(filter.matches(-5), isFalse);
      expect(filter.matches(null), isFalse);
    });

    test('Not equals zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.notEqualsZero);
      expect(filter.matches(0), isFalse);
      expect(filter.matches(100), isTrue);
      expect(filter.matches(-50), isTrue);
    });

    test('Greater than zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.greaterThanZero);
      expect(filter.matches(1), isTrue);
      expect(filter.matches(0.001), isTrue);
      expect(filter.matches(0), isFalse);
      expect(filter.matches(-10), isFalse);
    });

    test('Less than zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.lessThanZero);
      expect(filter.matches(-1), isTrue);
      expect(filter.matches(-0.001), isTrue);
      expect(filter.matches(0), isFalse);
      expect(filter.matches(10), isFalse);
    });

    test('Greater than or equal zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.greaterThanOrEqualZero);
      expect(filter.matches(0), isTrue);
      expect(filter.matches(10), isTrue);
      expect(filter.matches(-1), isFalse);
    });

    test('Less than or equal zero operator', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.lessThanOrEqualZero);
      expect(filter.matches(0), isTrue);
      expect(filter.matches(-10), isTrue);
      expect(filter.matches(1), isFalse);
    });

    test('Specific value comparisons (=, >, <, >=, <=, !=)', () {
      const eq50 = NumericFilterState(operator: NumericFilterOperator.equalsValue, targetValue: 50.0);
      expect(eq50.matches(50), isTrue);
      expect(eq50.matches(50.00001), isTrue);
      expect(eq50.matches(49.9), isFalse);

      const gt50 = NumericFilterState(operator: NumericFilterOperator.greaterThanValue, targetValue: 50.0);
      expect(gt50.matches(50.1), isTrue);
      expect(gt50.matches(50), isFalse);

      const lt50 = NumericFilterState(operator: NumericFilterOperator.lessThanValue, targetValue: 50.0);
      expect(lt50.matches(49.9), isTrue);
      expect(lt50.matches(50), isFalse);

      const gte50 = NumericFilterState(operator: NumericFilterOperator.greaterThanOrEqualValue, targetValue: 50.0);
      expect(gte50.matches(50), isTrue);
      expect(gte50.matches(51), isTrue);
      expect(gte50.matches(49), isFalse);

      const lte50 = NumericFilterState(operator: NumericFilterOperator.lessThanOrEqualValue, targetValue: 50.0);
      expect(lte50.matches(50), isTrue);
      expect(lte50.matches(49), isTrue);
      expect(lte50.matches(51), isFalse);

      const neq50 = NumericFilterState(operator: NumericFilterOperator.notEqualsValue, targetValue: 50.0);
      expect(neq50.matches(50), isFalse);
      expect(neq50.matches(51), isTrue);
    });

    test('Labels formatting in Arabic, French, English', () {
      const filter = NumericFilterState(operator: NumericFilterOperator.greaterThanZero);
      expect(filter.getLabel(AppLanguage.arabic), contains('أكبر تماماً من الصفر'));
      expect(filter.getLabel(AppLanguage.french), contains('supérieur à zéro'));
      expect(filter.getLabel(AppLanguage.english), contains('Greater than zero'));
    });
  });

  group('TableDateRange Tests', () {
    test('All dates preset matches everything', () {
      final range = TableDateRange.fromPreset(DateRangePreset.all);
      expect(range.isActive, isFalse);
      expect(range.isWithinRange(DateTime(2020, 1, 1)), isTrue);
      expect(range.isWithinRange(DateTime.now()), isTrue);
    });

    test('Today preset matches today only', () {
      final range = TableDateRange.fromPreset(DateRangePreset.today);
      expect(range.isActive, isTrue);
      final now = DateTime.now();
      expect(range.isWithinRange(now), isTrue);
      expect(range.isWithinRange(now.subtract(const Duration(days: 2))), isFalse);
    });

    test('Custom date range filtering', () {
      final range = TableDateRange(
        startDate: DateTime(2026, 1, 1),
        endDate: DateTime(2026, 1, 31),
        preset: DateRangePreset.custom,
      );

      expect(range.isWithinRange(DateTime(2026, 1, 15)), isTrue);
      expect(range.isWithinRange(DateTime(2026, 1, 1, 0, 0, 1)), isTrue);
      expect(range.isWithinRange(DateTime(2026, 1, 31, 23, 59, 59)), isTrue);
      expect(range.isWithinRange(DateTime(2025, 12, 31)), isFalse);
      expect(range.isWithinRange(DateTime(2026, 2, 1)), isFalse);
      expect(range.isWithinRange(null), isFalse);
    });
  });
}
