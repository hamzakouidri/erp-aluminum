import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

missing_methods = '''
  Future<int> insertCommandeDetail({
    required int idCommande,
    required double largeur,
    required double hauteur,
    required String windowType,
    required String partitionsJson,
    String game = "Standard",
    int qty = 1,
    String glass = "Simple",
    double price = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Commandes_details', {
      'id_commandes': idCommande,
      'largeur': largeur,
      'hauteur': hauteur,
      'windowType': windowType,
      'partitionsJson': partitionsJson,
      'game': game,
      'qty': qty,
      'glass': glass,
      'price': price,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteCommande(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Commandes', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readAchats() async {
    Database? myDb = await db;
    return await myDb!.query('Achats');
  }
'''

content = content.replace('  ////////////////////////// Commandes Details //////////////////////////', missing_methods + '\n  ////////////////////////// Commandes Details //////////////////////////')

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
