import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Screen/moustiquaire_screen.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('each mosquito-net type has its own price key', () {
    expect(
      MoustiquaireType.values.map(moustiquaireTypePriceKey),
      moustiquaireTypePriceKeys.map((entry) => entry.$1),
    );
  });

  test('mosquito-net prices are never taken as a shutter blade price', () {
    final price = WindowModel.resolveShutterSqmPrice(
      bladeName: 'Enroulable',
      bladeSubtype: 'normal',
      colorId: null,
      prices: const [
        {'blade_type': 'Moustiquaire_enroulable', 'color_id': 0, 'price_per_sqm': 6000},
        {'blade_type': 'Enroulable', 'color_id': 0, 'price_per_sqm': 8500},
      ],
    );
    expect(price, 8500);
  });
}
