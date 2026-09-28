import 'package:database_data/Commande/order_measurements_confirm_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('measurement confirmation instances', () {
    test(
      'a legacy default quantity of one expands to the ordered quantity',
      () {
        final instances = normalizeMeasurementInstances(
          originalQuantity: 3,
          originalWidth: 1200,
          originalHeight: 1400,
          defaultPosition: 'Salon',
          savedInstances: const [
            {'width': 1200, 'height': 1400, 'qty': 1, 'position': 'Salon'},
          ],
          confirmedInstances: const [],
        );

        expect(instances, hasLength(1));
        expect(instances.single['qty'], 3);
        expect(instances.single['width'], 1200);
        expect(instances.single['height'], 1400);
      },
    );

    test(
      'reopening ten different confirmed measurements preserves every piece',
      () {
        final confirmed = List.generate(
          10,
          (i) => {'width': 1200 + i, 'height': 1440 + i, 'position': 'Room $i'},
        );
        final instances = normalizeMeasurementInstances(
          originalQuantity: 10,
          originalWidth: 1200,
          originalHeight: 1440,
          defaultPosition: '',
          savedInstances: const [],
          confirmedInstances: confirmed,
        );
        expect(instances, hasLength(10));
        for (var i = 0; i < 10; i++) {
          expect(instances[i]['width'], 1200 + i);
          expect(instances[i]['height'], 1440 + i);
          expect(instances[i]['position'], 'Room $i');
          expect(instances[i]['qty'], 1);
        }
      },
    );

    test('a partial confirmation remains partial after reopening', () {
      final instances = normalizeMeasurementInstances(
        originalQuantity: 3,
        originalWidth: 1200,
        originalHeight: 1400,
        defaultPosition: '',
        savedInstances: const [
          {'width': 1180, 'height': 1390, 'qty': 2, 'position': 'Cuisine'},
        ],
        confirmedInstances: const [
          {'width': 1180, 'height': 1390, 'position': 'Cuisine'},
          {'width': 1180, 'height': 1390, 'position': 'Cuisine'},
        ],
      );

      expect(instances, hasLength(1));
      expect(instances.single['qty'], 2);
      expect(instances.single['width'], 1180);
      expect(instances.single['height'], 1390);
    });
  });
}
