import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';

void main() {
  test('series pairing stays inside the selected profile system', () {
    final aluminium = AluminumProfileSystem(
      id: 1,
      name: 'Aluminium 4000',
      type: 'Aluminium',
    );
    final sameSystem = AluminumProfileSystem(
      id: 1,
      name: 'Aluminium 4000',
      type: 'Aluminium',
    );
    final anotherAluminiumSystem = AluminumProfileSystem(
      id: 2,
      name: 'Aluminium 6000',
      type: 'Aluminium',
    );
    final pvc = AluminumProfileSystem(id: 3, name: 'PVC', type: 'PVC');

    expect(profileSystemsShareMaterial(aluminium, sameSystem), isTrue);
    expect(profileSystemsShareMaterial(aluminium, anotherAluminiumSystem), isFalse);
    expect(profileSystemsShareMaterial(aluminium, pvc), isFalse);
  });
}
