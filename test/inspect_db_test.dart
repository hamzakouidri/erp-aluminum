import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart';
import 'dart:io';

void main() {
  test('inspect database', () async {
    sqfliteFfiInit();
    final dbFactory = databaseFactoryFfi;
    final dataPath = await dbFactory.getDatabasesPath();
    final dbPath = join(dataPath, 'test.db');
    
    print('Opening database at: $dbPath');
    if (!await File(dbPath).exists()) {
      print('DB file does not exist at $dbPath');
      return;
    }
    
    final db = await dbFactory.openDatabase(dbPath, options: OpenDatabaseOptions(readOnly: true));
    
    print('\n=== CLIENTS ===');
    final clients = await db.query('Client');
    for (var c in clients) {
      print('Client #${c['id']}: ${c['firstname']} ${c['lastname']}');
    }
    
    print('\n=== COMMANDES WITH ADVANCE ===');
    final orders = await db.query('Commandes');
    for (var o in orders) {
      print('Order #${o['id']}: client_id=${o['client_id']}, total=${o['total']}, net_payable=${o['net_payable']}, advance_payment=${o['advance_payment']}, payment_status=${o['payment_status']}');
    }
    
    print('\n=== TREASURY ENTRIES ===');
    final treasury = await db.query('Treasury');
    for (var t in treasury) {
      print('Treasury #${t['id']}: type=${t['transaction_type']}, amount=${t['amount']}, ref=${t['reference_id']}, desc=${t['description']}, entity_type=${t['entity_type']}, entity_id=${t['entity_id']}, caisse=${t['caisse_name']}');
    }
    
    await db.close();
  });
}
