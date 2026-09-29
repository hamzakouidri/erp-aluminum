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
}
