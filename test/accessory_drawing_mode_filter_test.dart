import 'package:database_data/Commande/Systeme/profile_selector_dialog.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Map<String, dynamic> accessory(String name, String type) => {
        'name': name,
        'type': type,
      };

  test('opening selectors reject sliding espagnolettes and handles', () {
    final openingEspagnolette = accessory('Espagnolette PVC 120', 'Espagnolette');
    final slidingEspagnolette =
        accessory('Espagnolette Coulissante PVC', 'Espagnolette Coulissante');
    final openingHandle = accessory('Poignée Fenêtre', 'Poignée Fenêtre');
    final slidingHandle =
        accessory('Poignée Coulissante', 'Poignée Coulissante');

    expect(
      accessoryMatchesDrawingMode(
        openingEspagnolette,
        AccessoryDrawingMode.opening,
      ),
      isTrue,
    );
    expect(
      accessoryMatchesDrawingMode(
        slidingEspagnolette,
        AccessoryDrawingMode.opening,
      ),
      isFalse,
    );
    expect(
      accessoryMatchesDrawingMode(openingHandle, AccessoryDrawingMode.opening),
      isTrue,
    );
    expect(
      accessoryMatchesDrawingMode(slidingHandle, AccessoryDrawingMode.opening),
      isFalse,
    );
  });

  test('sliding selectors accept only sliding espagnolettes and handles', () {
    final openingEspagnolette = accessory('Espagnolette PVC 120', 'Espagnolette');
    final slidingEspagnolette =
        accessory('Espagnolette Coulissante PVC', 'Espagnolette Coulissante');
    final openingHandle = accessory('Poignée Fenêtre', 'Poignée Fenêtre');
    final slidingHandle =
        accessory('Poignée Coulissante', 'Poignée Coulissante');

    expect(
      accessoryMatchesDrawingMode(
        openingEspagnolette,
        AccessoryDrawingMode.sliding,
      ),
      isFalse,
    );
    expect(
      accessoryMatchesDrawingMode(
        slidingEspagnolette,
        AccessoryDrawingMode.sliding,
      ),
      isTrue,
    );
    expect(
      accessoryMatchesDrawingMode(openingHandle, AccessoryDrawingMode.sliding),
      isFalse,
    );
    expect(
      accessoryMatchesDrawingMode(slidingHandle, AccessoryDrawingMode.sliding),
      isTrue,
    );
  });

  test('Paumelles and Mifsal match as opening-only hinges', () {
    for (final hinge in [
      accessory('Paumelles Prolex', 'Paumelles'),
      accessory('Mifsal PVC', 'Mifsal'),
    ]) {
      expect(isHingeAccessory(hinge), isTrue);
      expect(
        accessoryMatchesDrawingMode(hinge, AccessoryDrawingMode.opening),
        isTrue,
      );
      expect(
        accessoryMatchesDrawingMode(hinge, AccessoryDrawingMode.sliding),
        isFalse,
      );
    }
  });
}
