import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final catalogue = [
    <String, dynamic>{'id': 4, 'name': 'Kit Volet 165 (renamed)'},
    <String, dynamic>{'id': 7, 'name': 'Kit Volet Moteur 180'},
  ];

  test('a renamed kit stays selected through its id', () {
    final saved = {
      'catalog_source': 'KitBundles',
      'id': 4,
      'name': 'Kit Volet 165',
    };
    expect(
      ComponentCalculator.selectedKitBundle(saved, catalogue)?['name'],
      'Kit Volet 165 (renamed)',
    );
  });

  test('a deleted kit is not replaced by another kit of the same name', () {
    final saved = {
      'catalog_source': 'KitBundles',
      'id': 99,
      'name': 'Kit Volet Moteur 180',
    };
    expect(ComponentCalculator.selectedKitBundle(saved, catalogue), isNull);
  });

  test('selections saved without an id still match by name', () {
    final saved = {
      'catalog_source': 'KitBundles',
      'name': 'Kit Volet Moteur 180',
    };
    expect(
      ComponentCalculator.selectedKitBundle(saved, catalogue)?['id'],
      7,
    );
  });

  test('values not saved from KitBundles are ignored', () {
    final saved = {'catalog_source': 'ShutterComponents', 'id': 4};
    expect(ComponentCalculator.selectedKitBundle(saved, catalogue), isNull);
    expect(ComponentCalculator.selectedKitBundle(null, catalogue), isNull);
  });
}
