import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('GlassSpecification clone and copyWith supports temperedOuter and temperedInner flags', () {
    const spec = GlassSpecification(
      structure: GlassStructure.double,
      processingOuter: GlassProcessing.lowE,
      processingInner: GlassProcessing.none,
      temperedOuter: true,
      temperedInner: false,
    );

    // Test clone
    final cloned = spec.clone();
    expect(cloned.temperedOuter, isTrue);
    expect(cloned.temperedInner, isFalse);
    expect(cloned.processingOuter, equals(GlassProcessing.lowE));

    // Test copyWith
    final updated = spec.copyWith(temperedInner: true);
    expect(updated.temperedOuter, isTrue);
    expect(updated.temperedInner, isTrue);
    expect(updated.processingOuter, equals(GlassProcessing.lowE));
  });

  test('GlassSpecification serialization supports temperedOuter and temperedInner flags', () {
    const spec = GlassSpecification(
      structure: GlassStructure.double,
      processingOuter: GlassProcessing.lowE,
      temperedOuter: true,
      temperedInner: true,
    );

    final map = spec.toMap();
    expect(map['temperedOuter'], isTrue);
    expect(map['temperedInner'], isTrue);

    final deserialized = glassSpecificationFromMap(map);
    expect(deserialized.temperedOuter, isTrue);
    expect(deserialized.temperedInner, isTrue);
    expect(deserialized.processingOuter, equals(GlassProcessing.lowE));
  });
}
