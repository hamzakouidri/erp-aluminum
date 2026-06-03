import sys
import re

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Update Commandes CREATE TABLE
pattern_commandes = r"CREATE TABLE Commandes \([\s\S]*?FOREIGN KEY \(client_id\) REFERENCES Client\(id\) ON DELETE CASCADE\s*\)"
new_commandes = '''CREATE TABLE Commandes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER NOT NULL,
      status TEXT,
      description TEXT,
      remise REAL DEFAULT 0.0,
      tva REAL DEFAULT 0.0,
      total REAL NOT NULL,
      advance_payment REAL DEFAULT 0.0,
      payment_status TEXT DEFAULT 'Unpaid',
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (client_id) REFERENCES Client(id) ON DELETE CASCADE
    )'''
content = re.sub(pattern_commandes, new_commandes, content)

# 2. Update insertCommande method
pattern_insert = r"Future<int> insertCommande\([\s\S]*?rawInsert\([\s\S]*?\);\n  \}"
new_insert = '''Future<int> insertCommande(
    int idClient,
    String status,
    String description,
    double remise,
    double tva,
    double total, {
    double advancePayment = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.rawInsert(
      'INSERT INTO Commandes (client_id, status, description, remise, tva, total, advance_payment, payment_status) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [idClient, status, description, remise, tva, total, advancePayment, advancePayment >= total ? 'Paid' : (advancePayment > 0 ? 'Partial' : 'Unpaid')],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> addAdvanceToCommande(int idCommande, double amount) async {
    Database? myDb = await db;
    var orderData = await myDb!.query('Commandes', where: 'id = ?', whereArgs: [idCommande]);
    if (orderData.isNotEmpty) {
      double currentAdvance = (orderData[0]['advance_payment'] as num?)?.toDouble() ?? 0.0;
      double total = (orderData[0]['total'] as num?)?.toDouble() ?? 0.0;
      double newAdvance = currentAdvance + amount;
      String newStatus = newAdvance >= total ? 'Paid' : 'Partial';
      var res = await myDb.update('Commandes', {
        'advance_payment': newAdvance,
        'payment_status': newStatus
      }, where: 'id = ?', whereArgs: [idCommande]);
      CloudSyncService().notifyChange();
      return res;
    }
    return 0;
  }'''
content = re.sub(pattern_insert, new_insert, content)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
