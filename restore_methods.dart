import 'dart:io';

void main() async {
  final file = File('lib/sql_database.dart');
  var content = await file.readAsString();

  final returnFunc = '''
  Future<void> returnAchatInvoice(
    int achatId,
    List<Map<String, dynamic>> returnedItems,
    double refundedAmount,
  ) async {
    Database? myDb = await db;
    if (myDb == null) return;

    for (var item in returnedItems) {
      final itemId = item['id'] as int;
      final returnQty = (item['returnQty'] as num).toDouble();
      final currentQty = (item['currentQty'] as num).toDouble();
      final remainingQty = currentQty - returnQty;

      if (remainingQty <= 0) {
        await myDb.delete('Achat_items', where: 'id = ?', whereArgs: [itemId]);
      } else {
        await myDb.update(
          'Achat_items',
          {'quantity': remainingQty},
          where: 'id = ?',
          whereArgs: [itemId],
        );
      }
    }

    if (refundedAmount > 0) {
      await myDb.insert('Treasury', {
        'transaction_type': 'Income',
        'amount': refundedAmount,
        'description': 'استرجاع من المورد - فاتورة مشتريات رقم \$achatId',
        'reference_id': achatId,
        'created_at': DateTime.now().toIso8601String(),
      });
    }

    final newItems = await myDb.query('Achat_items', where: 'achat_id = ?', whereArgs: [achatId]);
    double newTotal = 0.0;
    for (var i in newItems) {
      newTotal += ((i['quantity'] as num?)?.toDouble() ?? 0) * ((i['price'] as num?)?.toDouble() ?? 0);
    }
    
    String newStatus = newTotal == 0 ? 'Returned' : 'Partial Returned';
    
    final achatRows = await myDb.query('Achats', where: 'id = ?', whereArgs: [achatId]);
    if (achatRows.isNotEmpty) {
      double currentPaid = (achatRows.first['paid_amount'] as num?)?.toDouble() ?? 0.0;
      double newPaid = (currentPaid - refundedAmount).clamp(0.0, double.infinity);
      double newRemaining = (newTotal - newPaid).clamp(0.0, double.infinity);

      await myDb.update(
        'Achats',
        {
          'total': newTotal,
          'paid_amount': newPaid,
          'remaining_amount': newRemaining,
          'status': newStatus,
          'updated_at': DateTime.now().toIso8601String(),
        },
        where: 'id = ?',
        whereArgs: [achatId],
      );
    }

    CloudSyncService().notifyChange();
  }
''';

  final readNameFunc = '''
  Future<List<Map<String, dynamic>>> readAchatsBySupplierName(
    String supplierName,
  ) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Achats',
      where: 'supplier_name = ?',
      whereArgs: [supplierName],
      orderBy: 'created_at DESC',
    );
  }
''';

  if (!content.contains('returnAchatInvoice(')) {
    content = content.replaceFirst('  Future<int> deleteAchatItem(int id) async {', '$returnFunc\\n  Future<int> deleteAchatItem(int id) async {');
  }

  if (!content.contains('readAchatsBySupplierName(')) {
    content = content.replaceFirst('  Future<List<Map<String, dynamic>>> readAchatsBySupplier(', '$readNameFunc\\n  Future<List<Map<String, dynamic>>> readAchatsBySupplier(');
  }

  await file.writeAsString(content);
}
