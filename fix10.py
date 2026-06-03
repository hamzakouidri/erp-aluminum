import sys

# 1. Restore sql_database.dart missing methods
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
    return res;
  }

  Future<int> deleteCommande(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Commandes', where: 'id = ?', whereArgs: [id]);
    return res;
  }

  Future<List<Map<String, dynamic>>> readAchats() async {
    Database? myDb = await db;
    return await myDb!.query('Achats');
  }
}
'''
if 'insertCommandeDetail' not in content:
    # find the last closing brace
    idx = content.rfind('}')
    if idx != -1:
        content = content[:idx] + missing_methods
        with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
            f.write(content)

# 2. Fix price_management_screen.dart canChangePrices
with open('lib/Screen/price_management_screen.dart', 'r', encoding='utf-8') as f:
    price_content = f.read()

old_state = '''class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final SqlDatabase db = SqlDatabase();
'''
new_state = '''class _PriceManagementScreenState extends State<PriceManagementScreen> {
  final SqlDatabase db = SqlDatabase();
  bool get canChangePrices => Provider.of<AppSettingsProvider>(context, listen: false).canChangePrices();
'''
if 'bool get canChangePrices' not in price_content:
    price_content = price_content.replace(old_state, new_state)

with open('lib/Screen/price_management_screen.dart', 'w', encoding='utf-8') as f:
    f.write(price_content)
