import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/sql_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _TestDatabase extends SqlDatabase {
  _TestDatabase(this.connection);

  final Database connection;

  @override
  Future<Database?> get db async => connection;
}

const _locationId = 1;
const _white = 3;

Future<_TestDatabase> _openDatabase() async {
  sqfliteFfiInit();
  // Schema checks are cached per process; every test opens a new database.
  SqlDatabase.resetDb();
  SharedPreferences.setMockInitialValues({});
  final connection = await databaseFactoryFfi.openDatabase(
    inMemoryDatabasePath,
  );
  addTearDown(connection.close);
  await connection.execute(
    'CREATE TABLE Commandes (id INTEGER PRIMARY KEY, '
    'is_deleted INTEGER NOT NULL DEFAULT 0)',
  );
  await connection.execute('''
    CREATE TABLE CurrentStock (
      id INTEGER PRIMARY KEY,
      item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL,
      color_id INTEGER,
      location_id INTEGER NOT NULL,
      quantity REAL NOT NULL DEFAULT 0.0,
      updated_at TEXT
    )
  ''');
  await connection.execute('''
    CREATE TABLE InventoryTransactions (
      id INTEGER PRIMARY KEY,
      item_id INTEGER NOT NULL,
      item_type TEXT NOT NULL,
      color_id INTEGER,
      location_id INTEGER NOT NULL,
      transaction_type TEXT NOT NULL,
      quantity REAL NOT NULL,
      reference_id INTEGER,
      note TEXT,
      created_at TEXT
    )
  ''');
  for (final table in const [
    'Locations',
    'Colors',
    'Series',
    'ShutterComponents',
    'Joints',
    'Glass',
  ]) {
    await connection.execute(
      'CREATE TABLE $table (id INTEGER PRIMARY KEY, name TEXT)',
    );
  }
  await connection.execute('''
    CREATE TABLE Accessories (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    name TEXT NOT NULL,
    material_type TEXT NOT NULL DEFAULT 'Aluminium',
    scope TEXT NOT NULL DEFAULT 'Global',
    series_id INTEGER,
    series_ids TEXT,
    type TEXT NOT NULL,
    price REAL NOT NULL DEFAULT 0.0,
    screw_count INTEGER NOT NULL DEFAULT 0,
    is_moteur_screw INTEGER DEFAULT 0,
    is_caisson_screw INTEGER DEFAULT 0,
    is_batmo_screw INTEGER DEFAULT 0,
    is_bouchon_batmo_screw INTEGER DEFAULT 0,
    is_renfort_screw INTEGER DEFAULT 0,
    is_manivelle_screw INTEGER DEFAULT 0,
    is_tandem_screw INTEGER DEFAULT 0,
    is_kit_screw INTEGER DEFAULT 0,
    is_assembly_screw INTEGER DEFAULT 0,
    is_accessory_screw INTEGER DEFAULT 0,
    is_installation_screw INTEGER DEFAULT 0,
    is_gache_simple INTEGER DEFAULT 0,
    is_gache_double INTEGER DEFAULT 0,
    is_gache_porte INTEGER DEFAULT 0,
    is_lock_clef INTEGER DEFAULT 0,
    is_lock_condamnation INTEGER DEFAULT 0,
    is_default INTEGER NOT NULL DEFAULT 0,
    gache_accessory_id INTEGER,
    gache_count INTEGER NOT NULL DEFAULT 0,
    linked_accessory_id INTEGER,
    linked_accessory_count INTEGER NOT NULL DEFAULT 0,
    screw_accessory_id INTEGER,
    triangle_deduction_mm REAL NOT NULL DEFAULT 0.0,
    triangle_position_mode TEXT NOT NULL DEFAULT 'center',
    triangle_position_mm REAL NOT NULL DEFAULT 0.0,
    triangle_link_mode TEXT NOT NULL DEFAULT 'none',
    triangle_quantity INTEGER NOT NULL DEFAULT 1,
    is_active INTEGER NOT NULL DEFAULT 1
    )
  ''');
  await connection.execute(
    'CREATE TABLE Sections '
    '(id INTEGER PRIMARY KEY, name TEXT, code TEXT, series_id INTEGER)',
  );
  await connection.execute('''
    CREATE TABLE CatalogItemRules (
      id INTEGER PRIMARY KEY,
      item_table TEXT,
      item_id INTEGER,
      series_id INTEGER,
      role_key TEXT,
      is_active INTEGER DEFAULT 1
    )
  ''');
  for (final id in const [1, 2]) {
    await connection.insert('Commandes', {'id': id});
  }
  await connection.insert('Locations', {'id': _locationId, 'name': 'Main'});

  final database = _TestDatabase(connection);
  // Creates the reservation and remnant tables.
  await database.readStockAvailability(itemId: 1, itemType: 'Accessory');
  return database;
}

Future<void> _stock(
  Database connection,
  int itemId,
  double quantity, {
  int? colorId,
}) => connection.insert('CurrentStock', {
  'item_id': itemId,
  'item_type': 'Accessory',
  'color_id': colorId,
  'location_id': _locationId,
  'quantity': quantity,
});

WindowModel _window(SqlDatabase db, {String seriesName = 'TP67'}) {
  final window = WindowModel(
    db: db,
    width: 1000,
    height: 1200,
    profileThickness: 50,
  );
  window.activeSeries = AluminumSeries(
    id: 7,
    profileId: 1,
    name: seriesName,
    type: 'opening',
  );
  window.zones = [
    WindowZone(
      id: 'main',
      content: ZoneContent.doubleSash,
      boundary: const Rect.fromLTWH(50, 50, 900, 1100),
    ),
  ];
  return window;
}

Map<String, dynamic> _accessory(
  int id,
  String type, {
  String material = 'Aluminium',
  String scope = 'Global',
  String? seriesIds,
}) => {
  'id': id,
  'name': 'Part $id',
  'type': type,
  'price': 100.0,
  'material_type': material,
  'scope': scope,
  'series_ids': seriesIds,
  'is_active': 1,
};

void main() {
  test('category and quality are read from the saved type', () {
    expect(AccessoryCategory.of('Paumelles|جودة رفيعة'), 'Paumelles');
    expect(AccessoryCategory.qualityOf('Paumelles|جودة رفيعة'), 'جودة رفيعة');
    expect(AccessoryCategory.of('Verrou'), 'Verrou');
    expect(AccessoryCategory.qualityOf('Verrou'), '');
  });

  test('a part fits only its exact category, material and series', () async {
    final database = await _openDatabase();
    final window = _window(database);
    const hinges = AccessoryCategory.hinges;

    expect(window.accessoryFitsDrawing(_accessory(1, 'Paumelles|x'), hinges),
        isTrue);
    // Another category never fits, even with a similar name.
    expect(
      window.accessoryFitsDrawing(_accessory(2, 'Paumelles PVC|x'), hinges),
      isFalse,
    );
    expect(
      window.accessoryFitsDrawing(
        _accessory(3, 'Paumelles|x', material: 'PVC'),
        hinges,
      ),
      isFalse,
    );
    expect(
      window.accessoryFitsDrawing(
        _accessory(4, 'Paumelles|x', material: 'Both'),
        hinges,
      ),
      isTrue,
    );
    expect(
      window.accessoryFitsDrawing(
        _accessory(5, 'Paumelles|x', scope: 'Unique', seriesIds: ',7,'),
        hinges,
      ),
      isTrue,
    );
    expect(
      window.accessoryFitsDrawing(
        _accessory(6, 'Paumelles|x', scope: 'Unique', seriesIds: ',8,'),
        hinges,
      ),
      isFalse,
    );
    expect(
      window.accessoryFitsDrawing(
        {..._accessory(7, 'Paumelles|x'), 'is_active': 0},
        hinges,
      ),
      isFalse,
    );

    final pvcWindow = _window(database, seriesName: 'PVC 70');
    expect(
      pvcWindow.accessoryFitsDrawing(
        _accessory(3, 'Paumelles|x', material: 'PVC'),
        hinges,
      ),
      isTrue,
    );
  });

  test('a choice is shared with the cost table and can be undone', () async {
    final database = await _openDatabase();
    await database.connection.insert(
      'Accessories',
      _accessory(10, 'Paumelles|جودة رفيعة'),
    );
    final window = _window(database);
    const key = 'المفاصل (Hinges)';

    final candidates = await window.accessoryCandidates(
      AccessoryCategory.hinges,
    );
    expect(candidates.map((row) => row['id']), [10]);

    await window.setAccessoryChoice(key, candidates.single);
    expect(window.componentOverrides[key]?['id'], 10);
    expect(window.componentOverrides[key]?['calculated_price'], 100.0);
    expect(window.isAccessoryChosen(key), isTrue);

    await window.clearAccessoryChoice(key);
    expect(window.isAccessoryChosen(key), isFalse);
  });

  test('each handle kind uses its own cost-table row', () async {
    final database = await _openDatabase();
    final window = _window(database);
    final zone = window.zones.single;

    // Aluminium: the ordinary handle is the crémone.
    expect(window.handleSlotFor(zone)?.bomKey, 'كريمون (Cremone)');
    zone.usePvcHandleOnAlu = true;
    expect(
      window.handleSlotFor(zone)?.bomKey,
      'مقبض نافذة بي في سي (Poignée Fenêtre PVC)',
    );
    zone
      ..usePvcHandleOnAlu = false
      ..useOctoHandle = true;
    expect(window.handleSlotFor(zone)?.category, AccessoryCategory.octoHandle);

    zone
      ..useOctoHandle = false
      ..isSash105 = true
      ..lockType = LockType.clef;
    expect(window.handleSlotFor(zone)?.category, AccessoryCategory.doorHandleKey);
    zone.lockType = LockType.rouleau2000;
    expect(
      window.handleSlotFor(zone)?.bomKey,
      'مقبض كبير ماريشال 2 متر (Poignée Maréchal 2m)',
    );

    final pvcWindow = _window(database, seriesName: 'PVC 70');
    expect(
      pvcWindow.handleSlotFor(pvcWindow.zones.single)?.bomKey,
      'مقبض نافذة (Poignée Fenêtre)',
    );

    final fixed = WindowZone(
      id: 'fixed',
      content: ZoneContent.fixedGlass,
      boundary: const Rect.fromLTWH(0, 0, 100, 100),
    );
    expect(window.handleSlotFor(fixed), isNull);
  });

  test('the stock a handle choice must cover', () async {
    final database = await _openDatabase();
    final window = _window(database)..quantity = 3;
    final slot = window.handleSlotFor(window.zones.single)!;
    expect(window.handlesNeeded(slot), 3);
    window.zones.single.doubleSashHasTwoHandles = true;
    expect(window.handlesNeeded(slot), 6);
  });

  test('free stock leaves out other orders and follows the colour', () async {
    final database = await _openDatabase();
    final connection = database.connection;
    await _stock(connection, 20, 10, colorId: _white);
    await _stock(connection, 21, 5);
    await database.setOrderStockReservation(
      orderId: 1,
      reserved: true,
      stockDeductions: [
        {
          'item_id': 20,
          'item_type': 'Accessory',
          'color_id': _white,
          'location_id': _locationId,
          'quantity': 4.0,
        },
      ],
    );

    final free = await database.readFreeAccessoryStock(
      [20, 21, 22],
      colorId: _white,
    );
    expect(free[20], 6.0);
    // A colourless accessory counts its colourless stock in any colour.
    expect(free[21], 5.0);
    expect(free[22], 0.0);

    final ownOrder = await database.readFreeAccessoryStock(
      [20],
      colorId: _white,
      excludeOrderId: 1,
    );
    expect(ownOrder[20], 10.0);
  });
}
