import re

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

inventory_code = """
  // ==================== INVENTORY MANAGEMENT ====================
  Future<List<Map<String, dynamic>>> readLocations() async {
    Database? myDb = await db;
    return await myDb!.query('Locations', orderBy: 'id ASC');
  }

  Future<void> updateInventory({
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
    required double quantityChange,
    required String transactionType,
    int? referenceId,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return;

    await myDb.transaction((txn) async {
      // 1. Record the transaction
      await txn.insert('InventoryTransactions', {
        'item_id': itemId,
        'item_type': itemType,
        'color_id': colorId,
        'location_id': locationId,
        'quantity_change': quantityChange,
        'transaction_type': transactionType,
        'reference_id': referenceId,
        'created_at': DateTime.now().toIso8601String(),
      });

      // 2. Update current stock
      final String where;
      final List<Object?> whereArgs;

      if (colorId == null) {
        where = 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?';
        whereArgs = [itemId, itemType, locationId];
      } else {
        where = 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
        whereArgs = [itemId, itemType, colorId, locationId];
      }

      final stockRows = await txn.query('CurrentStock', where: where, whereArgs: whereArgs);
      
      if (stockRows.isNotEmpty) {
        double currentQty = (stockRows.first['quantity'] as num).toDouble();
        double newQty = currentQty + quantityChange;
        await txn.update(
          'CurrentStock',
          {'quantity': newQty, 'updated_at': DateTime.now().toIso8601String()},
          where: where,
          whereArgs: whereArgs,
        );
      } else {
        await txn.insert('CurrentStock', {
          'item_id': itemId,
          'item_type': itemType,
          'color_id': colorId,
          'location_id': locationId,
          'quantity': quantityChange,
          'updated_at': DateTime.now().toIso8601String(),
        });
      }
    });
    CloudSyncService().notifyChange();
  }

  Future<List<Map<String, dynamic>>> readCurrentStock(int locationId) async {
    Database? myDb = await db;
    if (myDb == null) return [];

    final stock = await myDb.query('CurrentStock', where: 'location_id = ? AND quantity != 0', whereArgs: [locationId]);
    List<Map<String, dynamic>> enrichedStock = [];

    for (var row in stock) {
      final itemType = row['item_type'] as String;
      final itemId = row['item_id'] as int;
      final colorId = row['color_id'] as int?;
      
      String itemName = 'مجهول';
      String colorName = '';

      if (colorId != null) {
        final colorRow = await myDb.query('Colors', columns: ['name'], where: 'id = ?', whereArgs: [colorId]);
        if (colorRow.isNotEmpty) colorName = colorRow.first['name'].toString();
      }

      if (itemType == 'Profile') {
        final itemRow = await myDb.query('Profile', columns: ['name'], where: 'id = ?', whereArgs: [itemId]);
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Accessory') {
        final itemRow = await myDb.query('Accessories', columns: ['name'], where: 'id = ?', whereArgs: [itemId]);
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Glass') {
        final itemRow = await myDb.query('Glass', columns: ['name'], where: 'id = ?', whereArgs: [itemId]);
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Shutter Component') {
        final itemRow = await myDb.query('ShutterComponents', columns: ['name'], where: 'id = ?', whereArgs: [itemId]);
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      } else if (itemType == 'Lame' || itemType == 'Glissiere' || itemType == 'Axe' || itemType == 'Caisson') {
        final itemRow = await myDb.query('ShutterComponents', columns: ['name'], where: 'id = ?', whereArgs: [itemId]);
        if (itemRow.isNotEmpty) itemName = itemRow.first['name'].toString();
      }

      enrichedStock.add({
        ...row,
        'item_name': itemName,
        'color_name': colorName,
      });
    }

    return enrichedStock;
  }

  Future<List<Map<String, dynamic>>> readInventoryTransactions({
    required int itemId,
    required String itemType,
    int? colorId,
    required int locationId,
  }) async {
    Database? myDb = await db;
    if (myDb == null) return [];
    
    final String where;
    final List<Object?> whereArgs;
    
    if (colorId == null) {
      where = 'item_id = ? AND item_type = ? AND color_id IS NULL AND location_id = ?';
      whereArgs = [itemId, itemType, locationId];
    } else {
      where = 'item_id = ? AND item_type = ? AND color_id = ? AND location_id = ?';
      whereArgs = [itemId, itemType, colorId, locationId];
    }

    return await myDb.query(
      'InventoryTransactions',
      where: where,
      whereArgs: whereArgs,
      orderBy: 'created_at DESC',
    );
  }
}
"""

content = re.sub(r'}\s*$', inventory_code, content)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
