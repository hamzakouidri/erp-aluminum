import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';

WindowModel _shutterWindow(String mechanism, {bool tunnel = false}) {
  final model = WindowModel(db: SqlDatabase(), width: 1200, height: 1400);
  model.hasShutter = true;
  model.shutterMechanism = mechanism;
  model.isCaissonTunnel = tunnel;
  return model;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('standardActiveVariants', () {
    test('a motor shutter uses embout and supports, never a tandem', () {
      final variants = ComponentCalculator.standardActiveVariants(
        _shutterWindow('محرك'),
      );
      expect(variants['كيت فولي موتور (Kit Volet Moteur)'], isTrue);
      expect(variants['الامبو (Embout)'], isTrue);
      expect(variants['سيبور رولمو (Support Roulement)'], isTrue);
      expect(variants['سيبور موتور (Support Moteur)'], isTrue);
      expect(variants['طانديم (Tandem)'], isFalse);
      expect(variants['كيت فولي (Kit Volet)'], isFalse);
    });

    test('a belt shutter uses the belt kit only', () {
      final variants = ComponentCalculator.standardActiveVariants(
        _shutterWindow('حزام'),
      );
      expect(variants['كيت فولي (Kit Volet)'], isTrue);
      expect(variants['الامبو (Embout)'], isFalse);
      expect(variants['طانديم (Tandem)'], isFalse);
      expect(variants['سيبور موتور (Support Moteur)'], isFalse);
    });

    test('a crank shutter uses the crank kits', () {
      final variants = ComponentCalculator.standardActiveVariants(
        _shutterWindow('مانيفال'),
      );
      expect(variants['كيت فولي مانيفر (Kit Volet Manivelle)'], isTrue);
      expect(variants['كيت مانيفر (Kit Manivelle)'], isTrue);
      expect(variants['كيت فولي (Kit Volet)'], isFalse);
    });

    test('a tunnel box uses its own kit and the tandem', () {
      final variants = ComponentCalculator.standardActiveVariants(
        _shutterWindow('محرك', tunnel: true),
      );
      expect(variants['كيت صندوق النفق (Kit Caisson Tunnel)'], isTrue);
      expect(variants['طانديم (Tandem)'], isTrue);
      expect(variants['كيت فولي موتور (Kit Volet Moteur)'], isFalse);
    });

    test('an X3D PVC motor with emergency crank needs no motor support', () {
      final model = _shutterWindow('محرك');
      model.activeSeries = AluminumSeries(
        id: 1,
        profileId: 1,
        name: 'PVC 70',
        type: 'pvc',
      );
      model.componentOverrides['الشرائح (Lames)'] = {'name': 'Lame X3D'};
      model.componentOverrides['المحرك (Moteur)'] = {
        'name': 'Motor',
        'motor_has_emergency_crank': 1,
      };
      final variants = ComponentCalculator.standardActiveVariants(model);
      expect(variants['سيبور موتور (Support Moteur)'], isFalse);
    });

    test('blade end caps follow the selected component', () {
      final model = _shutterWindow('حزام');
      expect(
        ComponentCalculator.standardActiveVariants(
          model,
        )['أغطية الشفرات (Bouchons Lames)'],
        isFalse,
      );
      model.componentOverrides['أغطية الشفرات (Bouchons Lames)'] = {'id': 3};
      expect(
        ComponentCalculator.standardActiveVariants(
          model,
        )['أغطية الشفرات (Bouchons Lames)'],
        isTrue,
      );
    });
  });

  group('user variant choices', () {
    test('choices made in the quantity table are applied everywhere', () {
      final model = _shutterWindow('محرك');
      model.shutterVariantChoices = {'طانديم (Tandem)': true};
      model.shutterVariantChoicesContext =
          ComponentCalculator.shutterVariantContext(model);

      expect(
        ComponentCalculator.standardActiveVariants(model)['طانديم (Tandem)'],
        isTrue,
      );
      expect(
        ComponentCalculator.standardActiveVariants(
          model,
          includeUserChoices: false,
        )['طانديم (Tandem)'],
        isFalse,
      );
    });

    test('choices made for another mechanism are ignored', () {
      final model = _shutterWindow('محرك');
      model.shutterVariantChoices = {'الامبو (Embout)': false};
      model.shutterVariantChoicesContext =
          ComponentCalculator.shutterVariantContext(model);
      model.shutterMechanism = 'حزام';

      expect(
        ComponentCalculator.standardActiveVariants(model)['الامبو (Embout)'],
        isFalse,
      );
      expect(
        ComponentCalculator.standardActiveVariants(
          model,
        )['كيت فولي (Kit Volet)'],
        isTrue,
      );
    });

    test('model-backed switches are never overridden by choices', () {
      final model = _shutterWindow('حزام');
      model.shutterVariantChoices = {'Verrou Central': true};
      model.shutterVariantChoicesContext =
          ComponentCalculator.shutterVariantContext(model);
      expect(
        ComponentCalculator.standardActiveVariants(model)['Verrou Central'],
        isFalse,
      );
    });

    test('choices survive save and reopen', () {
      final model = _shutterWindow('محرك');
      model.shutterVariantChoices = {'طانديم (Tandem)': true};
      model.shutterVariantChoicesContext =
          ComponentCalculator.shutterVariantContext(model);

      final restored = WindowModel(db: SqlDatabase());
      applyWindowModelFromMap(restored, model.toMap());
      expect(restored.shutterVariantChoices, {'طانديم (Tandem)': true});
      expect(
        restored.shutterVariantChoicesContext,
        model.shutterVariantChoicesContext,
      );
    });
  });
}
