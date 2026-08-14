import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';

Map<String, dynamic> kit(String name, String description) => {
  'name': name,
  'description': description,
};

void main() {
  group('kit description codes', () {
    test('normalizes codes without depending on case or separators', () {
      expect(normalizeKitDescriptionCode(' mt, '), 'MT');
      expect(kitHasDescriptionCode(kit('Motor', 'Mt'), 'MT'), isTrue);
      expect(kitHasDescriptionCode(kit('Volet', 'V'), 'MT'), isFalse);
    });

    test('selects the required size and every larger V kit', () {
      final kits = [
        kit('Kit volet 205', 'V'),
        kit('Kit volet Moteur 185', 'MT'),
        kit('Kit volet 155', 'v'),
        kit('Kit volet 185', 'V'),
        kit('Kit Manivelle', 'M'),
      ];

      expect(
        compatibleKitBundles(
          kits: kits,
          descriptionCode: 'V',
          minimumSizeMm: 155,
        ).map((row) => row['name']),
        ['Kit volet 155', 'Kit volet 185', 'Kit volet 205'],
      );
      expect(
        compatibleKitBundles(
          kits: kits,
          descriptionCode: 'V',
          minimumSizeMm: 185,
        ).map((row) => row['name']),
        ['Kit volet 185', 'Kit volet 205'],
      );
    });

    test('keeps motor, crank and tunnel bundles in their own codes', () {
      final kits = [
        kit('Kit volet 185', 'V'),
        kit('Kit volet Moteur 185', 'MT'),
        kit('Kit Manivelle', 'M'),
        kit('Kit Caisson Tunnel', 'CT'),
      ];

      expect(shutterKitCodeForMechanism('محرك'), 'MT');
      expect(shutterKitCodeForMechanism('مانيفال'), 'V');
      expect(
        compatibleKitBundles(
          kits: kits,
          descriptionCode: 'MT',
          minimumSizeMm: 185,
        ).single['name'],
        'Kit volet Moteur 185',
      );
      expect(
        compatibleKitBundles(
          kits: kits,
          descriptionCode: 'M',
          allowWithoutSize: true,
        ).single['name'],
        'Kit Manivelle',
      );
      expect(
        compatibleKitBundles(
          kits: kits,
          descriptionCode: 'CT',
          allowWithoutSize: true,
        ).single['name'],
        'Kit Caisson Tunnel',
      );
    });
  });
}
