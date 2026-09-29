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

  test('Order soft-delete, trash listing, restore, and permanent purge lifecycle', () async {
    final directory = await Directory.systemTemp.createTemp('erp_trash_test_');
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

    // 1. Insert a test client
    final clientId = await connection.insert('Client', {
      'firstname': 'Ahmed',
      'lastname': 'Benali',
      'phone1': '0555123456',
      'address': 'Algiers',
      'created_at': DateTime.now().toIso8601String(),
      'updated_at': DateTime.now().toIso8601String(),
    });

    // 2. Insert a test order
    final orderId = await connection.insert('Commandes', {
      'order_code': 101,
      'client_id': clientId,
      'status': 'En attente',
      'description': 'Fenêtre 2 vantaux',
      'total': 25000.0,
      'net_payable': 25000.0,
      'advance_payment': 0.0,
      'payment_status': 'Unpaid',
    });

    // Insert an item detail for this order
    await connection.insert('Commandes_details', {
      'id_commandes': orderId,
      'largeur': 1200,
      'hauteur': 1400,
      'game': 'Coulissant 67',
      'quantity': 2,
      'glass': 'Double vitrage',
      'color': 'Blanc',
      'volet': 'Sans volet',
      'accessories': 'Standard',
      'description': 'Coulissant test',
      'price': 25000.0,
    });

    // 3. Verify active orders contains the order
    final activeOrdersBefore = await sqlDb.readCommandesWithClients();
    expect(activeOrdersBefore.any((c) => c['id'] == orderId), isTrue);

    // 4. Verify trash is initially empty
    final trashBefore = await sqlDb.readTrashCommandesWithClients();
    expect(trashBefore, isEmpty);
    expect(await sqlDb.countTrashCommandes(), 0);

    // 5. Soft-delete the order (move to trash)
    final softDeletedCount = await sqlDb.deleteCommande(orderId);
    expect(softDeletedCount, 1);

    // 6. Verify order disappeared from active list
    final activeOrdersAfter = await sqlDb.readCommandesWithClients();
    expect(activeOrdersAfter.any((c) => c['id'] == orderId), isFalse);

    // 7. Verify order appears in trash with deleted_at timestamp
    final trashAfter = await sqlDb.readTrashCommandesWithClients();
    expect(trashAfter.length, 1);
    expect(trashAfter.first['id'], orderId);
    expect(trashAfter.first['is_deleted'], 1);
    expect(trashAfter.first['deleted_at'], isNotNull);
    expect(await sqlDb.countTrashCommandes(), 1);

    // Verify order details are still preserved while in trash
    final itemsInTrash = await sqlDb.readCommandeDetails(orderId);
    expect(itemsInTrash.length, 1);
    expect(itemsInTrash.first['largeur'], 1200);

    // 8. Restore the order
    final restoredCount = await sqlDb.restoreCommande(orderId);
    expect(restoredCount, 1);

    // 9. Verify order is back in active list and gone from trash
    final activeOrdersRestored = await sqlDb.readCommandesWithClients();
    expect(activeOrdersRestored.any((c) => c['id'] == orderId), isTrue);
    expect(await sqlDb.countTrashCommandes(), 0);
    expect(await sqlDb.readTrashCommandesWithClients(), isEmpty);

    // 10. Soft-delete again and permanently delete from trash
    await sqlDb.deleteCommande(orderId);
    expect(await sqlDb.countTrashCommandes(), 1);

    final permanentDeletedCount = await sqlDb.deleteCommandePermanently(orderId);
    expect(permanentDeletedCount, 1);

    // 11. Verify completely purged from Commandes and Commandes_details
    expect(await sqlDb.countTrashCommandes(), 0);
    final activeOrdersFinal = await sqlDb.readCommandesWithClients();
    expect(activeOrdersFinal.any((c) => c['id'] == orderId), isFalse);
    final itemsAfterPurge = await sqlDb.readCommandeDetails(orderId);
    expect(itemsAfterPurge, isEmpty);
  });
}
