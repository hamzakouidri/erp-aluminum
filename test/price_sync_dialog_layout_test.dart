import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/widgets/price_sync_banner.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({
      'app_language': AppLanguage.arabic.index,
      'app_language_explicit': true,
    });
    await Supabase.initialize(
      url: 'https://example.supabase.co',
      publishableKey: 'price-sync-layout-test-key',
    );
  });

  testWidgets('price sync settings dialog does not overflow on a phone', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(320, 568);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final settings = AppSettingsProvider();
    addTearDown(settings.dispose);
    await settings.setLanguage(AppLanguage.arabic);

    await tester.pumpWidget(
      ChangeNotifierProvider<AppSettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showPriceSyncSettingsDialog(context),
                child: const Text('فتح'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('تحديث الأسعار'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.byType(SwitchListTile).first);
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);

    await tester.tap(find.text('إغلاق'));
    await tester.pumpAndSettle();
    tester.view.physicalSize = const Size(568, 320);
    await tester.pump();

    await tester.tap(find.text('فتح'));
    await tester.pumpAndSettle();

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
