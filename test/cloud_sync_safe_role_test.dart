import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:database_data/settings/app_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppSettingsProvider preserves manager role from preferences during reloadPermissions', () async {
    SharedPreferences.setMockInitialValues({
      'user_role': 'manager',
      'workshop_code': 'workshop_123',
      'user_display_name': 'Test Manager',
    });

    final settings = AppSettingsProvider();
    await settings.loadSettings();

    expect(settings.userRole, 'manager');
    expect(settings.isManager, true);

    await settings.reloadPermissions();

    // The user role must not be downgraded to 'worker' before Firestore snapshot arrives
    expect(settings.userRole, 'manager');
    expect(settings.isManager, true);
  });
}
