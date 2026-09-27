import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('SQLCipher recovers a mobile connection without an options cast error',
      () async {
    const channel = MethodChannel('com.davidmartos96.sqflite_sqlcipher');
    final calls = <MethodCall>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'openDatabase') {
        return {'id': 42, 'recovered': true, 'recoveredInTransaction': true};
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    final db = await openDatabase(
      '/mobile_reopen_regression.db',
      password: 'test-only-password',
    );
    try {
      final open = calls.singleWhere((call) => call.method == 'openDatabase');
      expect((open.arguments as Map)['password'], 'test-only-password');
      expect(calls.any((call) =>
          call.method == 'execute' &&
          (call.arguments as Map)['sql'] == 'ROLLBACK'), isTrue);
    } finally {
      await db.close();
    }
  });
}
