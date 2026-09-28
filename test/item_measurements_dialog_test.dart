import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/Commande/item_measurements_dialog.dart';
import 'package:database_data/settings/app_settings.dart';

void main() {
  testWidgets(
    'desktop RTL places statuses opposite measurements and mobile stacks them',
    (tester) async {
      Future<void> render(double width) async {
        await tester.binding.setSurfaceSize(Size(width, 1000));
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: Directionality(
                textDirection: TextDirection.rtl,
                child: ItemMeasurementsDialog(
                  detail: {
                    'quantity': 2,
                    'largeur': 1200,
                    'hauteur': 1440,
                    'confirmed_mesures_json': jsonEncode([
                      {'width': 1200, 'height': 1440},
                      {'width': 1300, 'height': 1450},
                    ]),
                    'measurement_allocations': <Map<String, dynamic>>[],
                  },
                  language: AppLanguage.arabic,
                  canConfirm: false,
                  isSaved: true,
                  embedded: true,
                ),
              ),
            ),
          ),
        );
      }

      addTearDown(() => tester.binding.setSurfaceSize(null));
      await render(1200);
      final measurement = find.text('1200 × 1440 مم');
      final status = find.text('التصنيع: غير مصنّعة (0 / 1)').first;
      expect(
        tester.getRect(status).right,
        lessThan(tester.getRect(measurement).left),
      );
      expect(tester.takeException(), isNull);
      await render(390);
      expect(
        tester.getRect(status).top,
        greaterThan(tester.getRect(measurement).bottom),
      );
      expect(tester.takeException(), isNull);
    },
  );

  Future<void> open(
    WidgetTester tester, {
    List<dynamic> confirmed = const [],
    bool saved = true,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: ItemMeasurementsDialog(
          detail: {
            'quantity': 10,
            'largeur': 1200,
            'hauteur': 1440,
            'confirmed_mesures_json': jsonEncode(confirmed),
          },
          language: AppLanguage.english,
          canConfirm: saved,
          isSaved: saved,
        ),
      ),
    );
  }

  testWidgets(
    'order details embed measurements without a dialog or edit controls',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 320,
              child: ItemMeasurementsDialog(
                detail: {'quantity': 1, 'largeur': 1200, 'hauteur': 1440},
                language: AppLanguage.arabic,
                canConfirm: false,
                isSaved: true,
                embedded: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('1200 × 1440 مم'), findsOneWidget);
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(FilledButton), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'details show manufacturing and glass progress beside measurements',
    (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SingleChildScrollView(
              child: ItemMeasurementsDialog(
                detail: {
                  'quantity': 2,
                  'largeur': 1200,
                  'hauteur': 1440,
                  'confirmed_mesures_json': jsonEncode([
                    {'width': 1200, 'height': 1440},
                    {'width': 1300, 'height': 1450},
                  ]),
                  'measurement_allocations': [
                    {
                      'unit_index': 1,
                      'quantity': 1,
                      'is_manufactured': 1,
                      'is_glass_installed': 0,
                    },
                    {
                      'unit_index': 2,
                      'quantity': 1,
                      'is_manufactured': 1,
                      'is_glass_installed': 1,
                    },
                  ],
                },
                language: AppLanguage.english,
                canConfirm: false,
                isSaved: true,
                embedded: true,
              ),
            ),
          ),
        ),
      );
      expect(find.text('Manufacturing: Manufactured (2 / 2)'), findsOneWidget);
      expect(
        find.text('Glass: Glass partially installed (1 / 2)'),
        findsOneWidget,
      );
      expect(find.text('Glass: Glass not installed (0 / 1)'), findsOneWidget);
      expect(find.text('Glass: Glass installed (1 / 1)'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('shows initial measurements and confirmation action', (
    tester,
  ) async {
    await open(tester);
    expect(find.text('1200 × 1440 mm'), findsOneWidget);
    expect(find.textContaining('Quantity: 10'), findsOneWidget);
    expect(find.text('Confirm measurements'), findsOneWidget);
  });

  testWidgets(
    'shows ten distinct saved measurements without confirmation action',
    (tester) async {
      await open(
        tester,
        confirmed: List.generate(
          10,
          (i) => {'width': 1200 + i, 'height': 1440 + i, 'position': 'Room $i'},
        ),
      );
      expect(find.text('Measurements confirmed'), findsOneWidget);
      for (var i = 0; i < 10; i++) {
        expect(find.text('${1200 + i} × ${1440 + i} mm'), findsOneWidget);
      }
      expect(find.text('Confirm measurements'), findsNothing);
    },
  );

  testWidgets('partial confirmation shows remaining quantity separately', (
    tester,
  ) async {
    await open(
      tester,
      confirmed: [
        {'width': 1190, 'height': 1430},
      ],
    );
    expect(find.text('Confirmed: 1 of 10'), findsOneWidget);
    expect(find.textContaining('Quantity: 9'), findsOneWidget);
    expect(find.text('Confirm measurements'), findsOneWidget);
  });

  testWidgets('unsaved items show dimensions and save guidance', (
    tester,
  ) async {
    await open(tester, saved: false);
    expect(find.text('1200 × 1440 mm'), findsOneWidget);
    expect(
      find.text('Save the order before confirming measurements.'),
      findsOneWidget,
    );
    expect(find.text('Confirm measurements'), findsNothing);
  });
}
