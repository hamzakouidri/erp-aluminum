import 'dart:convert';
import 'package:database_data/services/offline_account_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  test('offline account preserves verified deadline, block and permissions', () async {
    final account = {
      'userId': 'user-1',
      'blocked': true,
      'permissions': {'edit_orders': false},
      'subscription': {'status': 'expired', 'ends_at': '2026-01-01T00:00:00Z'},
    };
    SharedPreferences.setMockInitialValues({
      '${accountCachePrefix}user-1': jsonEncode(account),
    });
    final prefs = await SharedPreferences.getInstance();
    expect(readOfflineAccount(prefs, 'user-1'), account);
    expect(readOfflineAccount(prefs, 'user-2'), isNull);
  });

  test('workshop code and mismatched or corrupt cache never grant access', () async {
    SharedPreferences.setMockInitialValues({'workshop_code': 'ABC', 'user_role': 'manager'});
    final prefs = await SharedPreferences.getInstance();
    expect(readOfflineAccount(prefs, 'user-1'), isNull);
    await prefs.setString('${accountCachePrefix}user-1', jsonEncode({'userId': 'other'}));
    expect(readOfflineAccount(prefs, 'user-1'), isNull);
    await prefs.setString('${accountCachePrefix}user-1', '{bad');
    expect(readOfflineAccount(prefs, 'user-1'), isNull);
  });
}
