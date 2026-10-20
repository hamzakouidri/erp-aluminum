import 'package:database_data/utils/price_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('mobile accessory card price summary', () {
    test('shows the base price when no color prices exist', () {
      expect(formatAccessoryCardPrice(1250, const []), '1250 DA');
    });

    test('shows one price when all colors share it', () {
      expect(formatAccessoryCardPrice(0, const [850, 850, 850]), '850 DA');
    });

    test('shows the visible range when color prices differ', () {
      expect(
        formatAccessoryCardPrice(0, const [1500, 900, 1200]),
        '900 – 1500 DA',
      );
    });
  });
}
