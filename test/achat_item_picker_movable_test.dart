import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:database_data/settings/localization.dart';
import 'package:provider/provider.dart';
import 'package:database_data/Screen/achat_item_picker.dart';
import 'package:database_data/settings/app_settings.dart';

void main() {
  testWidgets('AchatItemPicker renders in embedded mode without crashing',
      (WidgetTester tester) async {
    final settings = AppSettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AchatItemPicker(
              achatId: 1,
              isEmbedded: true,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(AchatItemPicker), findsOneWidget);
  });

  testWidgets('AchatItemPicker has initial category "All" (كل المواد)',
      (WidgetTester tester) async {
    final settings = AppSettingsProvider();

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AppSettingsProvider>.value(value: settings),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: AchatItemPicker(
              achatId: 1,
              isEmbedded: true,
            ),
          ),
        ),
      ),
    );

    // Initial category label "كل المواد", in the chosen language.
    expect(
      find.text(Localization.translate('كل المواد', settings.language)),
      findsOneWidget,
    );
    // Profile filter initial label "كل البروفيلات"
    expect(
      find.text(Localization.translate('كل البروفيلات', settings.language)),
      findsOneWidget,
    );
  });
}
