import 'package:database_data/Screen/tempered_glass_work_screen.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('glass work opens and glass type can be changed', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsProvider();
    await settings.loadSettings();
    addTearDown(settings.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: TemperedGlassWorkScreen()),
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    final glassType = find.byWidgetPredicate(
      (widget) => widget is DropdownButtonFormField<String> &&
          const ['شفاف', 'ملون', 'عاكس', 'مصفح', 'معتّم']
              .contains(widget.initialValue),
    );
    expect(glassType, findsOneWidget);
    final field = tester.widget<DropdownButtonFormField<String>>(glassType);
    expect(field.initialValue, 'شفاف');
    await tester.ensureVisible(glassType);
    await tester.tap(glassType);
    await tester.pumpAndSettle();
    final tinted = find.text('Teinté').last;
    await tester.tap(tinted);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(tester.widget<DropdownButtonFormField<String>>(glassType).initialValue,
        'ملون');
  });

  testWidgets('profiles and gaskets open from the toolbar', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsProvider();
    await settings.loadSettings();
    addTearDown(settings.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: TemperedGlassWorkScreen()),
      ),
    );
    await tester.pumpAndSettle();

    final button = find.text('Profilés & joints');
    expect(button, findsOneWidget);
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Joint entre fixe et porte (pièce)'), findsOneWidget);
    await tester.tap(find.text('Fermer'));
    await tester.pumpAndSettle();
    expect(find.text('Joint entre fixe et porte (pièce)'), findsNothing);
  });

  testWidgets('sablage region dialog shows error when end <= start', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final settings = AppSettingsProvider();
    await settings.loadSettings();
    addTearDown(settings.dispose);
    await tester.binding.setSurfaceSize(const Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>.value(
        value: settings,
        child: const MaterialApp(home: TemperedGlassWorkScreen()),
      ),
    );
    await tester.pumpAndSettle();

    // Find sablage menu button
    final sablageBtn = find.textContaining('Sablage');
    if (sablageBtn.evaluate().isNotEmpty) {
      await tester.tap(sablageBtn.first);
      await tester.pumpAndSettle();

      final addRegionItem = find.textContaining('Ajouter une zone');
      if (addRegionItem.evaluate().isNotEmpty) {
        await tester.tap(addRegionItem.first);
        await tester.pumpAndSettle();

        // Check dialog title exists
        expect(find.textContaining('zone de sablage'), findsOneWidget);

        // Find Start and End text fields
        final textFields = find.byType(TextField);
        expect(textFields, findsAtLeastNWidgets(2));

        // Enter 440 in both start and end
        await tester.enterText(textFields.at(0), '440');
        await tester.enterText(textFields.at(1), '440');
        await tester.pumpAndSettle();

        // Tap Ajouter
        final ajouterBtn = find.widgetWithText(FilledButton, 'Ajouter');
        await tester.tap(ajouterBtn);
        await tester.pumpAndSettle();

        // Dialog should still be open and display error message
        expect(find.textContaining('zone de sablage'), findsOneWidget);
        expect(find.byIcon(Icons.error_outline), findsOneWidget);

        // Fix the end value to 880
        await tester.enterText(textFields.at(1), '880');
        await tester.pumpAndSettle();

        // Tap Ajouter again
        await tester.tap(ajouterBtn);
        await tester.pumpAndSettle();

        // Dialog should now be closed
        expect(find.textContaining('zone de sablage'), findsNothing);
      }
    }
  });
}
