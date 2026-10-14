import 'dart:io';

import 'package:database_data/sql_database.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _TemporaryPaths extends PathProviderPlatform {
  _TemporaryPaths(this.path);
  final String path;

  @override
  Future<String?> getApplicationSupportPath() async => path;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('client overpayment stays in Treasury and pays the next order', () async {
    final directory = await Directory.systemTemp.createTemp(
      'erp_client_credit_test_',
    );
    final originalPaths = PathProviderPlatform.instance;
    PathProviderPlatform.instance = _TemporaryPaths(directory.path);
    SharedPreferences.setMockInitialValues({});
    addTearDown(() async {
      PathProviderPlatform.instance = originalPaths;
      await directory.delete(recursive: true);
    });

    final sqlDb = SqlDatabase();
    final connection = await sqlDb.initDb();
    addTearDown(connection.close);

    final now = DateTime.now().toUtc().toIso8601String();
    final clientId = await connection.insert('Client', {
      'firstname': 'Credit',
      'lastname': 'Client',
      'phone1': '0555000001',
      'created_at': now,
      'updated_at': now,
    });
    final firstOrderId = await connection.insert('Commandes', {
      'order_code': 201,
      'client_id': clientId,
      'status': 'Nouveau',
      'description': 'First order',
      'total': 100.0,
      'net_payable': 100.0,
      'advance_payment': 0.0,
      'payment_status': 'Unpaid',
      'created_at': now,
      'updated_at': now,
    });

    await sqlDb.insertTreasury(
      'Encaissement',
      150.0,
      'Overpayment',
      referenceId: firstOrderId,
      entityType: 'Client',
      entityId: clientId,
    );

    var firstOrder = (await connection.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [firstOrderId],
    )).single;
    expect(firstOrder['advance_payment'], 100.0);
    expect(firstOrder['payment_status'], 'Paid');
    final receipts = await connection.query(
      'Treasury',
      where: "entity_type = 'Client' AND entity_id = ?",
      whereArgs: [clientId],
    );
    expect(receipts, hasLength(1));
    expect(receipts.single['amount'], 150.0);

    final secondOrderId = await connection.insert('Commandes', {
      'order_code': 202,
      'client_id': clientId,
      'status': 'Nouveau',
      'description': 'Next order',
      'total': 80.0,
      'net_payable': 80.0,
      'advance_payment': 0.0,
      'payment_status': 'Unpaid',
      'created_at': DateTime.now()
          .toUtc()
          .add(const Duration(days: 30))
          .toIso8601String(),
      'updated_at': now,
    });
    await sqlDb.reconcileClientPayments(clientId);

    final secondOrder = (await connection.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [secondOrderId],
    )).single;
    expect(secondOrder['advance_payment'], 50.0);
    expect(secondOrder['payment_status'], 'Partial');

    firstOrder = (await connection.query(
      'Commandes',
      where: 'id = ?',
      whereArgs: [firstOrderId],
    )).single;
    expect(firstOrder['advance_payment'], 100.0);
    expect(await connection.query('Treasury'), hasLength(1));
  });
}
