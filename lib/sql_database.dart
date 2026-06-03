import 'package:path/path.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';
import 'package:intl/intl.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class SqlDatabase {
  static Database? _db;

  static void resetDb() {
    _db = null;
  }

  String get now => DateTime.now().toIso8601String();

  String get date => DateFormat('yyyy-MM-dd').format(DateTime.now());

  Future<Database?> get db async {
    if (_db != null) return _db!;
    _db = await initDb();
    return _db;
  }

  Future<Database> initDb() async {
    String dbName = 'test.db';
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
        if (doc.exists) {
          final workshopId = doc.data()?['workshopId'];
          if (workshopId != null) {
            dbName = 'window_calculator_$workshopId.db';
          }
        }
      }
    } catch (e) {
      print('Error getting workshopId for DB name: $e');
    }

    String dataPath = await getDatabasesPath();
    String path = join(dataPath, dbName);
    Database myDb = await openDatabase(
      path,
      version: 10,
      // تم رفع الإصدار ليتضمن جميع الجداول الجديدة، مع الحفاظ على البيانات القديمة عبر دوال الترقية
      password: "password",
      onCreate: _onCreate,
      onUpgrade: _onUpgrade,
    );

    // Safely add columns if they are missing (for existing users who didn't get them from _onCreate)
    try { await myDb.execute("ALTER TABLE Accessories ADD COLUMN material_type TEXT NOT NULL DEFAULT 'Aluminium'"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Accessories ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Accessories ADD COLUMN series_id INTEGER"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Accessories ADD COLUMN series_ids TEXT"); } catch (_) {}
    
    try { await myDb.execute("ALTER TABLE Joints ADD COLUMN type TEXT NOT NULL DEFAULT 'Global'"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Joints ADD COLUMN scope TEXT NOT NULL DEFAULT 'Global'"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Joints ADD COLUMN series_id INTEGER"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Joints ADD COLUMN series_ids TEXT"); } catch (_) {}
    try { await myDb.execute("ALTER TABLE Sections ADD COLUMN couvre_joint_width REAL NOT NULL DEFAULT 0.0"); } catch (_) {}

    return myDb;
  }

  // 🟢 دالة الترقية: تقوم بإنشاء الجداول للمستخدمين الذين لديهم التطبيق مسبقاً
  void _onUpgrade(Database db, int oldVersion, int newVersion) async {
    if (oldVersion < 2) {
      await db.execute('''
                CREATE TABLE Series (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      price_per_meter REAL NOT NULL DEFAULT 0.0,
      FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE
    )
      ''');
      await db.execute('''
        CREATE TABLE Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          code TEXT NOT NULL,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          glass_deduction REAL NOT NULL,
          weight_per_meter REAL NOT NULL,
          couvre_joint_width REAL NOT NULL DEFAULT 0.0,
          FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 3) {
      await db.execute('''
        CREATE TABLE Achats (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          invoice_number TEXT NOT NULL,
          supplier_name TEXT NOT NULL,
          status TEXT NOT NULL DEFAULT 'Active',
          total REAL NOT NULL DEFAULT 0.0,
          created_at TEXT NOT NULL DEFAULT (datetime('now')),
          updated_at TEXT NOT NULL DEFAULT (datetime('now'))
        )
      ''');
    }
    if (oldVersion < 4) {
      // ترقية جدول Achats لإضافة مسار الصورة
      await db.execute('ALTER TABLE Achats ADD COLUMN image_path TEXT;');
      // إنشاء جدول سلع الفاتورة Achat_items
      await db.execute('''
        CREATE TABLE Achat_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        achat_id INTEGER NOT NULL,
        item_code TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'Other',
        item_id INTEGER NOT NULL DEFAULT 0,
        color_id INTEGER,
        quantity REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (achat_id) REFERENCES Achats(id) ON DELETE CASCADE
      )
      ''');
    }
    if (oldVersion < 5) {
      // Colors Table
      await db.execute('''
            CREATE TABLE Colors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      hex_code TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'Global',
      price REAL NOT NULL DEFAULT 0.0
    )
      ''');
      // Accessories Table
      await db.execute('''
          CREATE TABLE IF NOT EXISTS Accessories (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            material_type TEXT NOT NULL DEFAULT 'Aluminium',
            scope TEXT NOT NULL DEFAULT 'Global',
            series_id INTEGER,
            series_ids TEXT,
            type TEXT NOT NULL,
            price REAL NOT NULL DEFAULT 0.0
          )
      ''');
      // Joints/Gaskets Table
      await db.execute('''
        CREATE TABLE Joints (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          thickness REAL NOT NULL,
          price_per_meter REAL NOT NULL,
          type TEXT NOT NULL DEFAULT 'Global',
          scope TEXT NOT NULL DEFAULT 'Global',
          series_id INTEGER,
          series_ids TEXT
        )
      ''');
      // Glass Table
      await db.execute('''
        CREATE TABLE Glass (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          type TEXT NOT NULL,
          thickness REAL NOT NULL,
          price_per_sqm REAL NOT NULL
        )
      ''');
      // Sections Table
      await db.execute('''
        CREATE TABLE IF NOT EXISTS Sections (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          nom TEXT NOT NULL,
          type TEXT NOT NULL,
          quantite INTEGER NOT NULL,
          reference TEXT NOT NULL,
          price REAL NOT NULL DEFAULT 0.0
        )
      ''');
      // Shutter Components Table
      await db.execute('''
        CREATE TABLE ShutterComponents (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          name TEXT NOT NULL,
          component_type TEXT NOT NULL,
          price REAL NOT NULL,
          unit TEXT NOT NULL,
          created_at TEXT DEFAULT CURRENT_TIMESTAMP
        )
      ''');
      
      // Seed initial Shutter Components for old DB upgrades
      final List<Map<String, dynamic>> shutterSeeds = [
        {'name': 'ستار أبيض', 'component_type': 'Lame', 'price': 8000.0, 'unit': 'sqm'},
        {'name': 'ستار خشبي', 'component_type': 'Lame', 'price': 12000.0, 'unit': 'sqm'},
      ];
      for (var seed in shutterSeeds) {
        await db.insert('ShutterComponents', seed);
      }
    }
    if (oldVersion < 6) {
      try {
        await db.execute('ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;');
      } catch (e) {
        print('Column price_per_meter already exists or error: ');
      }
      try {
        await db.execute('ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;');
      } catch (e) {
        print('Column price already exists or error: ');
      }
    }
    if (oldVersion < 7) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SeriesColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          series_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(series_id, color_id)
        )
      ''');
      await db.execute('''
        CREATE TABLE IF NOT EXISTS SectionColorPrices (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          section_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          price REAL NOT NULL DEFAULT 0.0,
          UNIQUE(section_id, color_id)
        )
      ''');
    }
    if (oldVersion < 8) {
      await db.execute('''
        CREATE TABLE IF NOT EXISTS ProfileColors (
          profile_id INTEGER NOT NULL,
          color_id INTEGER NOT NULL,
          PRIMARY KEY (profile_id, color_id),
          FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE,
          FOREIGN KEY (color_id) REFERENCES Colors(id) ON DELETE CASCADE
        )
      ''');
    }
    if (oldVersion < 9) {
      await db.execute('DROP TABLE IF EXISTS Client');
      await db.execute('''
        CREATE TABLE Client (
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          firstname TEXT NOT NULL,
          lastname TEXT NOT NULL,
          phone1 TEXT,
          phone2 TEXT,
          email TEXT,
          address TEXT,
          created_at TEXT NOT NULL,
          updated_at TEXT NOT NULL
        )
      ''');
    }
    if (oldVersion < 10) {
      try {
        await db.execute("ALTER TABLE Achat_items ADD COLUMN item_type TEXT NOT NULL DEFAULT 'Other';");
        await db.execute("ALTER TABLE Achat_items ADD COLUMN item_id INTEGER NOT NULL DEFAULT 0;");
        await db.execute("ALTER TABLE Achat_items ADD COLUMN color_id INTEGER;");
      } catch (e) {
        print('Achat_items columns already exist or error: $e');
      }
    }
  }

  void _onCreate(Database db, int version) async {
    await db.execute('''
      CREATE TABLE IF NOT EXISTS SeriesColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        series_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(series_id, color_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS SectionColorPrices (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        section_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        price REAL NOT NULL DEFAULT 0.0,
        UNIQUE(section_id, color_id)
      )
    ''');

    await db.execute('''
      CREATE TABLE IF NOT EXISTS ProfileColors (
        profile_id INTEGER NOT NULL,
        color_id INTEGER NOT NULL,
        PRIMARY KEY (profile_id, color_id),
        FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE,
        FOREIGN KEY (color_id) REFERENCES Colors(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
    CREATE TABLE Profile ( 
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL UNIQUE,
      type TEXT NOT NULL
    )
    ''');

    await db.execute('''
      CREATE TABLE Series (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      profile_id INTEGER NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      price_per_meter REAL NOT NULL DEFAULT 0.0,
      FOREIGN KEY (profile_id) REFERENCES Profile(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
      CREATE TABLE Sections (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      series_id INTEGER NOT NULL,
      code TEXT NOT NULL,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      glass_deduction REAL NOT NULL DEFAULT 0.0,
      weight_per_meter REAL NOT NULL DEFAULT 0.0,
      couvre_joint_width REAL NOT NULL DEFAULT 0.0,
      FOREIGN KEY (series_id) REFERENCES Series(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE TABLE Client (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      firstname TEXT NOT NULL,
      lastname TEXT NOT NULL,
      phone1 TEXT,
      phone2 TEXT,
      email TEXT,
      address TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    )
    ''');

    await db.execute('''
    CREATE TABLE Commandes (
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
    )
    ''');

    await db.execute('''
    CREATE TABLE Commandes_details (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      id_commandes INTEGER NOT NULL,
      largeur INTEGER NOT NULL,
      hauteur INTEGER NOT NULL,
      game TEXT NOT NULL,
      quantity INTEGER NOT NULL,
      glass TEXT NOT NULL,
      color TEXT NOT NULL,
      volet TEXT NOT NULL,
      accessories TEXT NOT NULL,
      description TEXT NOT NULL,
      price DECIMAL(10,2) NOT NULL,
      window_type TEXT, 
      partitions_json TEXT, 
      FOREIGN KEY (id_commandes) REFERENCES Commandes(id) ON DELETE CASCADE
    )
    ''');

    await db.execute('''
    CREATE TABLE Achats (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      invoice_number TEXT NOT NULL,
      supplier_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'Active',
      total REAL NOT NULL DEFAULT 0.0,
      image_path TEXT,
      created_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
    ''');

    await db.execute('''
    CREATE TABLE Achat_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        achat_id INTEGER NOT NULL,
        item_code TEXT NOT NULL,
        item_name TEXT NOT NULL,
        item_type TEXT NOT NULL DEFAULT 'Other',
        item_id INTEGER NOT NULL DEFAULT 0,
        color_id INTEGER,
        quantity REAL NOT NULL,
        price REAL NOT NULL,
        FOREIGN KEY (achat_id) REFERENCES Achats(id) ON DELETE CASCADE
      )
    ''');

    await db.execute('''
    CREATE TABLE Employees (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      uid TEXT NOT NULL UNIQUE,
      email TEXT NOT NULL,
      name TEXT NOT NULL,
      permissions_json TEXT NOT NULL
    )
    ''');

    await db.execute('''
        CREATE TABLE Colors (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      hex_code TEXT NOT NULL,
      type TEXT NOT NULL DEFAULT 'Global',
      price REAL NOT NULL DEFAULT 0.0
    )
    ''');

    await db.execute('''
    CREATE TABLE Accessories (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      price REAL NOT NULL,
      material_type TEXT NOT NULL DEFAULT 'Aluminium',
      scope TEXT NOT NULL DEFAULT 'Global',
      series_id INTEGER,
      series_ids TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE Joints (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      thickness REAL NOT NULL,
      price_per_meter REAL NOT NULL,
      type TEXT NOT NULL DEFAULT 'Global',
      scope TEXT NOT NULL DEFAULT 'Global',
      series_id INTEGER,
      series_ids TEXT
    )
    ''');

    await db.execute('''
    CREATE TABLE Glass (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      type TEXT NOT NULL,
      thickness REAL NOT NULL,
      price_per_sqm REAL NOT NULL
    )
    ''');

    await db.execute('''
    CREATE TABLE ShutterComponents (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      name TEXT NOT NULL,
      component_type TEXT NOT NULL,
      price REAL NOT NULL,
      unit TEXT NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    ''');
    
    // Seed initial Shutter Components for new DB
    final List<Map<String, dynamic>> initialShutters = [
      {'name': 'ستار أبيض', 'component_type': 'Lame', 'price': 8000.0, 'unit': 'sqm'},
      {'name': 'ستار بني/خشبي', 'component_type': 'Lame', 'price': 12000.0, 'unit': 'sqm'},
    ];
    for (var shutter in initialShutters) {
      await db.insert('ShutterComponents', shutter);
    }
  }

  //////////////////////////////////// Profile //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readProfile() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Profile');
  }

  Future<int> insertProfile(String name, String type) async {
    Database? myDb = await db;
    var res = await myDb!.rawInsert(
      'INSERT INTO Profile (name, type) VALUES (?, ?)',
      [name, type],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateProfile(int id, String name, String type) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Profile',
      {'name': name, 'type': type},
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteProfile(int id) async {
    Database? myDb = await db;
    var res = await myDb!.rawDelete('DELETE FROM Profile WHERE id = ?', [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Series //////////////////////////////////////
  // 🟢 دوال السلسلة الجديدة
  Future<List<Map<String, dynamic>>> readSeriesByProfile(int profileId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Series',
      where: 'profile_id = ?',
      whereArgs: [profileId],
    );
  }

  Future<int> insertSeries(int profileId, String name, String type, {double pricePerMeter = 0.0}) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Series', {
      'profile_id': profileId,
      'name': name,
      'type': type,
      'price_per_meter': pricePerMeter,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<double> getSeriesColorPrice(int seriesId, int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query('SeriesColorPrices', where: 'series_id = ? AND color_id = ?', whereArgs: [seriesId, colorId]);
    if (res.isNotEmpty) {
      return (res.first['price'] as num).toDouble();
    }
    return 0.0;
  }

  Future<int> updateSeries(int id, int profileId, String name, String type, {double pricePerMeter = 0.0}) async {
    Database? myDb = await db;
    var res = await myDb!.update('Series', {
      'profile_id': profileId,
      'name': name,
      'type': type,
      'price_per_meter': pricePerMeter,
    }, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteSeries(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Series', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Sections //////////////////////////////////////
  // 🟢 دوال المقاطع الجديدة
  Future<List<Map<String, dynamic>>> readSectionsBySeries(int seriesId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Sections',
      where: 'series_id = ?',
      whereArgs: [seriesId],
    );
  }

  Future<int> insertSection({
    required int seriesId,
    required String code,
    required String name,
    required String type, // frame, sash, mullion, parclose
    required double thickness,
    required double glassDeduction,
    required double weightPerMeter,
    double couvreJointWidth = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Sections', {
      'series_id': seriesId,
      'code': code,
      'name': name,
      'type': type,
      'thickness': thickness,
      'glass_deduction': glassDeduction,
      'weight_per_meter': weightPerMeter,
      'couvre_joint_width': couvreJointWidth,
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateSection(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Sections',
      data,
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteSection(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Sections', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Client //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readClient() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Client');
  }

  Future<int> insertClient(
    String firstname,
    String lastname,
    String phone1,
    String phone2,
    String email,
    String address,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.rawInsert(
      'INSERT INTO Client (firstname, lastname, phone1, phone2, email, address, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
      [firstname, lastname, phone1, phone2, email, address, now, now],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateClient(
    int id,
    String firstname,
    String lastname,
    String phone1,
    String phone2,
    String email,
    String address,
    String updatedAt,
  ) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Client',
      {
        'firstname': firstname,
        'lastname': lastname,
        'phone1': phone1,
        'phone2': phone2,
        'email': email,
        'address': address,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteClient(int id) async {
    Database? myDb = await db;
    var res = await myDb!.rawDelete('DELETE FROM Client WHERE id = ?', [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> searchClient(String query) async {
    final dbClient = await db;
    List<String> terms = query.trim().split(RegExp(r'\s+')).where((s) => s.isNotEmpty).toList();
    if (terms.isEmpty) {
      return await dbClient!.rawQuery('SELECT * FROM Client');
    }

    String whereClause = terms.map((_) {
      return "(firstname LIKE ? OR lastname LIKE ? OR phone1 LIKE ? OR phone2 LIKE ? OR address LIKE ?)";
    }).join(" AND ");

    List<String> whereArgs = [];
    for (String term in terms) {
      whereArgs.addAll(['%$term%', '%$term%', '%$term%', '%$term%', '%$term%']);
    }

    return await dbClient!.rawQuery('SELECT * FROM Client WHERE $whereClause', whereArgs);
  }

  Future<List<Map<String, dynamic>>> getClientById(int id) async {
    final dbclient = await db;
    return await dbclient!.query('Client', where: 'id = ?', whereArgs: [id]);
  }

  ///////////////////////////////// Commande ////////////////////////////////
  Future<List<Map<String, dynamic>>> readCommande() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('SELECT * FROM Commandes');
  }

  Future<List<Map<String, dynamic>>> readCommandesWithClients() async {
    Database? myDb = await db;
    return await myDb!.rawQuery('''
      SELECT c.*, cl.firstname, cl.lastname, cl.phone1 as phone 
      FROM Commandes c 
      LEFT JOIN Client cl ON c.id_client = cl.id
      ORDER BY c.created_at DESC
    ''');
  }

  Future<int> insertCommande(
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
  }

  Future<int> insertAchat(String invoiceNumber, String supplierName, double total, {String? imagePath}) async {
    Database? myDb = await db;
    var res = await myDb!.insert(
      'Achats',
      {
        'invoice_number': invoiceNumber,
        'supplier_name': supplierName,
        'status': 'Active',
        'total': total,
        'image_path': imagePath,
        'created_at': DateTime.now().toIso8601String(),
        'updated_at': DateTime.now().toIso8601String(),
      },
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> insertAchatItem({
    required int achatId,
    required String itemCode,
    required String itemName,
    required double quantity,
    required double price,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert(
      'Achat_items',
      {
        'achat_id': achatId,
        'item_code': itemCode,
        'item_name': itemName,
        'quantity': quantity,
        'price': price,
      },
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<Map<String, dynamic>>> readAchatItems(int achatId) async {
    Database? myDb = await db;
    return await myDb!.query(
      'Achat_items',
      where: 'achat_id = ?',
      whereArgs: [achatId],
    );
  }

  Future<int> updateAchatStatus(int id, String status) async {
    Database? myDb = await db;
    var res = await myDb!.update(
      'Achats',
      {
        'status': status,
        'updated_at': DateTime.now().toIso8601String(),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteAchat(int id) async {
    Database? myDb = await db;
    var res = await myDb!.rawDelete('DELETE FROM Achats WHERE id = ?', [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Colors //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readColors() async {
    Database? myDb = await db;
    var result = await myDb!.query('Colors');
    if (result.isEmpty) {
      await _insertDefaultColors(myDb);
      result = await myDb.query('Colors');
    }
    return result;
  }

  Future<void> _insertDefaultColors(Database myDb) async {
    final defaults = [
      {'name': 'أبيض', 'hex_code': '#FFFFFF', 'type': 'Global'},
      {'name': 'بني', 'hex_code': '#795548', 'type': 'Global'},
      {'name': 'رمادي', 'hex_code': '#9E9E9E', 'type': 'Global'},
      {'name': 'أسود', 'hex_code': '#000000', 'type': 'Global'},
      {'name': 'بيج', 'hex_code': '#F5F5DC', 'type': 'Global'},
    ];
    for (var c in defaults) {
      await myDb.insert('Colors', c);
    }
  }

  Future<int> insertColor(String name, String hexCode, String type, {double price = 0.0}) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Colors', {'name': name, 'hex_code': hexCode, 'type': type, 'price': price});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateColor(int id, String name, String hexCode, String type, {double price = 0.0}) async {
    Database? myDb = await db;
    var res = await myDb!.update('Colors', {'name': name, 'hex_code': hexCode, 'type': type, 'price': price}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteColor(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Colors', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<List<int>> getProfilesForColor(int colorId) async {
    Database? myDb = await db;
    var res = await myDb!.query('ProfileColors', where: 'color_id = ?', whereArgs: [colorId]);
    return res.map((e) => e['profile_id'] as int).toList();
  }

  Future<void> setProfilesForColor(int colorId, List<int> profileIds) async {
    Database? myDb = await db;
    await myDb!.delete('ProfileColors', where: 'color_id = ?', whereArgs: [colorId]);
    for (int profileId in profileIds) {
      await myDb.insert('ProfileColors', {'profile_id': profileId, 'color_id': colorId});
    }
  }

  Future<List<Map<String, dynamic>>> getColorsForProfile(int profileId) async {
    Database? myDb = await db;
    
    // Ensure defaults exist before querying
    var all = await myDb!.query('Colors');
    if (all.isEmpty) {
      await _insertDefaultColors(myDb);
    }

    return await myDb.rawQuery('''
      SELECT c.* FROM Colors c
      LEFT JOIN ProfileColors pc ON c.id = pc.color_id
      WHERE c.type = 'عام (Global)' OR c.type = 'Global'
         OR ( (c.type = 'فريد (Unique)' OR c.type = 'Unique') AND pc.profile_id = ? )
      GROUP BY c.id
    ''', [profileId]);
  }


  //////////////////////////////////// Accessories //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readAccessories() async {
    Database? myDb = await db;
    return await myDb!.query('Accessories');
  }

  Future<int> insertAccessory(Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Accessories', data);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateAccessory(int id, Map<String, dynamic> data) async {
    Database? myDb = await db;
    var res = await myDb!.update('Accessories', data, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteAccessory(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Accessories', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Joints //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readJoints() async {
    Database? myDb = await db;
    return await myDb!.query('Joints');
  }

  Future<int> insertJoint(String name, double thickness, double pricePerMeter) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Joints', {'name': name, 'thickness': thickness, 'price_per_meter': pricePerMeter});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateJoint(int id, String name, double thickness, double pricePerMeter) async {
    Database? myDb = await db;
    var res = await myDb!.update('Joints', {'name': name, 'thickness': thickness, 'price_per_meter': pricePerMeter}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteJoint(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Joints', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// Glass //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readGlass() async {
    Database? myDb = await db;
    return await myDb!.query('Glass');
  }

  Future<int> insertGlass(String name, String type, double thickness, double pricePerSqm) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Glass', {'name': name, 'type': type, 'thickness': thickness, 'price_per_sqm': pricePerSqm});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateGlass(int id, String name, String type, double thickness, double pricePerSqm) async {
    Database? myDb = await db;
    var res = await myDb!.update('Glass', {'name': name, 'type': type, 'thickness': thickness, 'price_per_sqm': pricePerSqm}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteGlass(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Glass', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  //////////////////////////////////// ShutterComponents //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readShutterComponents() async {
    Database? myDb = await db;
    return await myDb!.query('ShutterComponents');
  }

  Future<int> insertShutterComponent(String name, String componentType, double price, String unit) async {
    Database? myDb = await db;
    var res = await myDb!.insert('ShutterComponents', {'name': name, 'component_type': componentType, 'price': price, 'unit': unit});
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateShutterComponent(int id, String name, String componentType, double price, String unit) async {
    Database? myDb = await db;
    var res = await myDb!.update('ShutterComponents', {'name': name, 'component_type': componentType, 'price': price, 'unit': unit}, where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteShutterComponent(int id) async {
    Database? myDb = await db;
    var res = await myDb!.delete('ShutterComponents', where: 'id = ?', whereArgs: [id]);
    CloudSyncService().notifyChange();
    return res;
  }


  //////////////////////////////////// Employees //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readEmployees() async {
    Database? myDb = await db;
    return await myDb!.query('Employees');
  }

  Future<int> insertEmployee(String uid, String email, String name, String permissionsJson) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Employees', {
      'uid': uid,
      'email': email,
      'name': name,
      'permissions_json': permissionsJson
    });
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> updateEmployeePermissions(String uid, String permissionsJson) async {
    Database? myDb = await db;
    var res = await myDb!.update('Employees', {
      'permissions_json': permissionsJson
    }, where: 'uid = ?', whereArgs: [uid]);
    CloudSyncService().notifyChange();
    return res;
  }

  Future<int> deleteEmployee(String uid) async {
    Database? myDb = await db;
    var res = await myDb!.delete('Employees', where: 'uid = ?', whereArgs: [uid]);
    CloudSyncService().notifyChange();
    return res;
  }


  //////////////////////////////////// Treasury //////////////////////////////////////
  Future<List<Map<String, dynamic>>> readTreasury() async {
    Database? myDb = await db;
    return await myDb!.query('Treasury', orderBy: 'created_at DESC');
  }

  Future<int> insertTreasury(String transactionType, double amount, String description, {int? referenceId, String? recordedBy}) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Treasury', {
      'transaction_type': transactionType,
      'amount': amount,
      'description': description,
      'reference_id': referenceId,
      'recorded_by': recordedBy ?? 'مدير الورشة'
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

  Future<Map<String, dynamic>> exportAllData() async {
    Database? myDb = await db;
    final List<String> tables = [
      'Profile', 'Series', 'Sections', 'Client', 'Commandes', 'Commandes_details',
      'Achats', 'Achat_items', 'Colors', 'Accessories', 'Joints', 'Glass', 
      'Commandes_details', 'Commandes', 'Client', 'Sections', 'Series', 'Profile',
      'ShutterComponents', 'SeriesColorPrices', 'SectionColorPrices', 'ProfileColors', 'Employees', 'Treasury', 'WorkerTransactions'
    ];
    Map<String, dynamic> data = {};
    for (String table in tables) {
      try {
        data[table] = await myDb!.query(table);
      } catch (e) {
        data[table] = []; // fallback
      }
    }
    return data;
  }

  // ==================== Global Catalog Methods ====================
  Future<Map<String, dynamic>> exportGlobalCatalog() async {
    Database? myDb = await db;
    final List<String> catalogTables = [
      'Profile', 'Series', 'Sections', 'Colors', 'Accessories', 'Joints', 'Glass',
      'ShutterComponents', 'SeriesColorPrices', 'SectionColorPrices', 'ProfileColors', 'AccessoryColorPrices'
    ];
    Map<String, dynamic> data = {};
    for (String table in catalogTables) {
      try {
        data[table] = await myDb!.query(table);
      } catch (e) {
        data[table] = [];
      }
    }
    return data;
  }

  Future<void> importGlobalCatalog(Map<String, dynamic> data) async {
    Database? myDb = await db;
    final List<String> catalogTables = [
      'ProfileColors', 'SectionColorPrices', 'SeriesColorPrices', 'AccessoryColorPrices',
      'ShutterComponents', 'Glass', 'Joints', 'Accessories', 'Colors',
      'Sections', 'Series', 'Profile'
    ];
    
    await myDb!.transaction((txn) async {
      // Insert new catalog data or Update existing data (UPSERT) to preserve local relationships and quantities
      for (String table in data.keys) {
        if (!catalogTables.contains(table)) continue; // Only import catalog tables
        List<dynamic> rows = data[table] ?? [];
        for (var row in rows) {
          try {
            await txn.insert(
              table, 
              Map<String, dynamic>.from(row),
              conflictAlgorithm: ConflictAlgorithm.replace,
            );
          } catch (e) {
            print('Error inserting into $table: $e');
          }
        }
      }
    });
  }
  // ==================== تصفير البيانات الشخصية ====================
  Future<void> clearPersonalData() async {
    final myDb = await db;
    await myDb!.transaction((txn) async {
      await txn.delete('Client');
      await txn.delete('Commandes');
      await txn.delete('Commandes_details');
      await txn.delete('Achats');
      await txn.delete('Achat_items');
    });
    CloudSyncService().notifyChange();
  }

  Future<int> setSeriesColorPrice(int seriesId, int colorId, double price) async {
    Database? myDb = await db;
    var res = await myDb!.query('SeriesColorPrices', where: 'series_id = ? AND color_id = ?', whereArgs: [seriesId, colorId]);
    if (res.isEmpty) {
      var res = await myDb.insert('SeriesColorPrices', {'series_id': seriesId, 'color_id': colorId, 'price': price});
      CloudSyncService().notifyChange();
      return res;
    } else {
      var res = await myDb.update('SeriesColorPrices', {'price': price}, where: 'series_id = ? AND color_id = ?', whereArgs: [seriesId, colorId]);
      CloudSyncService().notifyChange();
      return res;
    }
  }

  Future<int> setSectionColorPrice(int sectionId, int colorId, double price) async {
    Database? myDb = await db;
    var res = await myDb!.query('SectionColorPrices', where: 'section_id = ? AND color_id = ?', whereArgs: [sectionId, colorId]);
    if (res.isEmpty) {
      var res = await myDb.insert('SectionColorPrices', {'section_id': sectionId, 'color_id': colorId, 'price': price});
      CloudSyncService().notifyChange();
      return res;
    } else {
      var res = await myDb.update('SectionColorPrices', {'price': price}, where: 'section_id = ? AND color_id = ?', whereArgs: [sectionId, colorId]);
      CloudSyncService().notifyChange();
      return res;
    }
  }


  Future<void> importAllData(Map<String, dynamic> data) async {
    Database? myDb = await db;
    final List<String> tables = [
      'WorkerTransactions', 'Treasury', 'Employees', 'ProfileColors', 'SectionColorPrices', 'SeriesColorPrices', 'AccessoryColorPrices', 'ShutterComponents', 'Glass', 'Joints',
      'Accessories', 'Colors', 'Achat_items', 'Achats', 'Commandes_details',
      'Commandes', 'Client', 'Sections', 'Series', 'Profile'
    ];
    
    await myDb!.transaction((txn) async {
      // 1. حذف البيانات الحالية بعكس الترتيب
      for (String table in tables) {
        try {
          await txn.delete(table);
        } catch (e) {
          // تجاهل الخطأ لو كان الجدول فارغ أو غير موجود
        }
      }
      
      // 2. إدخال البيانات الجديدة بالترتيب الصحيح (نفس الترتيب المحفوظ)
      for (String table in data.keys) {
        List<dynamic> rows = data[table] ?? [];
        for (var row in rows) {
          try {
            await txn.insert(table, Map<String, dynamic>.from(row));
          } catch (e) {
            print('Error inserting into $table: $e');
          }
        }
      }
    });
  }

  Future<int> insertCommandeDetail({
    required int idCommande,
    required double largeur,
    required double hauteur,
    required String windowType,
    required String partitionsJson,
    String game = "Standard",
    int qty = 1,
    String glass = "Simple",
    String color = "",
    String volet = "",
    String accessories = "",
    String description = "",
    double price = 0.0,
  }) async {
    Database? myDb = await db;
    var res = await myDb!.insert('Commandes_details', {
      'id_commandes': idCommande,
      'largeur': largeur,
      'hauteur': hauteur,
      'window_type': windowType,
      'partitions_json': partitionsJson,
      'game': game,
      'qty': qty,
      'glass': glass,
      'color': color,
      'volet': volet,
      'accessories': accessories,
      'description': description,
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

  // Accessory Color Prices Methods
  Future<int> setAccessoryColorPrice(int accessoryId, int colorId, double price) async {
    Database? myDb = await db;
    var existing = await myDb!.query('AccessoryColorPrices',
        where: 'accessory_id = ? AND color_id = ?',
        whereArgs: [accessoryId, colorId]);

    if (existing.isNotEmpty) {
      return await myDb.update(
        'AccessoryColorPrices',
        {'price': price},
        where: 'accessory_id = ? AND color_id = ?',
        whereArgs: [accessoryId, colorId],
      );
    } else {
      return await myDb.insert('AccessoryColorPrices', {
        'accessory_id': accessoryId,
        'color_id': colorId,
        'price': price,
      });
    }
  }

  Future<List<Map<String, dynamic>>> getAccessoryColorPrices(int accessoryId) async {
    Database? myDb = await db;
    return await myDb!.query('AccessoryColorPrices',
        where: 'accessory_id = ?', whereArgs: [accessoryId]);
  }
}
