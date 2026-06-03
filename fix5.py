import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Update Commandes export/import lists
content = content.replace(
    "'Employees', 'ProfileColors', 'SeriesColorPrices', 'ShutterComponents', 'Glass', 'Joints',",
    "'WorkerTransactions', 'Treasury', 'Employees', 'ProfileColors', 'SeriesColorPrices', 'ShutterComponents', 'Glass', 'Joints',"
)

content = content.replace(
    "'ShutterComponents', 'SeriesColorPrices', 'ProfileColors', 'Employees'",
    "'ShutterComponents', 'SeriesColorPrices', 'ProfileColors', 'Employees', 'Treasury', 'WorkerTransactions'"
)

methods = '''
  //////////////////////////////////// Treasury //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readTreasury() async {
    Database? myDb = await db;
    return await myDb!.query('Treasury', orderBy: 'created_at DESC');
  }

  Future<int> insertTreasury(String transactionType, double amount, String description, {int? referenceId}) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Treasury', {
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      'reference_id': referenceId
    });
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// WorkerTransactions //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readWorkerTransactions(String workerUid) async {
    Database? myDb = await db;
    return await myDb!.query('WorkerTransactions', where: 'worker_uid = ?', whereArgs: [workerUid], orderBy: 'created_at DESC');
  }

  Future<int> insertWorkerTransaction(String workerUid, double amount, String transactionType, String note) async {
    Database? myDb = await db;
    var res = await myDb!.insert('WorkerTransactions', {
      'worker_uid': workerUid,
      'amount': amount,
      'transaction_type': transactionType,
      'note': note
    });
    CloudSyncService().notifyChange();
    return res;
  }
'''

content = content.replace('  Future<Map<String, dynamic>> exportAllData() async {', methods + '\n  Future<Map<String, dynamic>> exportAllData() async {')

# Update insertCommande method
old_insert_commande = '''  Future<int> insertCommande(
    int idClient,
    String status,
    String description,
    double remise,
    double tva,
    double total,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.rawInsert(
      'INSERT INTO Commandes (id_client, status, description, remise, tva, total) VALUES (?, ?, ?, ?, ?, ?)',
      [idClient, status, description, remise, tva, total],
    );'''

new_insert_commande = '''  Future<int> insertCommande(
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
    );'''
content = content.replace(old_insert_commande, new_insert_commande)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
