import re

file_path = "lib/Commande/Systeme/cost_summary_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

robust_safe_load = """
  Future<void> _loadData() async {
    final dbInstance = (await db.db)!;
    
    Future<List<Map<String, dynamic>>> safeQuery(String table) async {
      try {
        return await dbInstance.query(table);
      } catch (e) {
        print("Error loading $table: $e");
        if (table == 'SeriesColorPrices') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS SeriesColorPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              series_id INTEGER NOT NULL,
              color_id INTEGER NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              UNIQUE(series_id, color_id)
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Colors') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Colors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              hex_code TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'Global',
              price REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
             await dbInstance.execute('ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;');
          } catch(e){}
          return await dbInstance.query(table);
        } else if (table == 'Series') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Series (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              profile_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price_per_meter REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
             await dbInstance.execute('ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;');
          } catch(e){}
          return await dbInstance.query(table);
        } else if (table == 'Glass') {
           await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Glass (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Shutters') {
           await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Shutters (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              color_id INTEGER,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Accessories') {
           await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Accessories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Joints') {
           await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Joints (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_meter REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        }
        return [];
      }
    }

    final sList = await safeQuery('Series');
    final gList = await safeQuery('Glass');
    final shList = await safeQuery('Shutters');
    final jList = await safeQuery('Joints');
    final aList = await safeQuery('Accessories');
    final cList = await safeQuery('Colors');

    Map<int, Map<int, double>> tempPrices = {};
    try {
      final pricesData = await safeQuery('SeriesColorPrices');
      for (var row in pricesData) {
        int sId = row['series_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempPrices.containsKey(sId)) {
          tempPrices[sId] = {};
        }
        tempPrices[sId]![cId] = p;
      }
    } catch (e) {
      print("Error parsing SeriesColorPrices: $e");
    }

    if (!mounted) return;
    setState(() {
      seriesList = sList;
      glassList = gList;
      shutterList = shList;
      jointList = jList;
      accessoryList = aList;
      colorList = cList;
      seriesColorPrices = tempPrices;

      if (seriesList.isNotEmpty) selectedSeries = seriesList.first;
      if (glassList.isNotEmpty) selectedGlass = glassList.first;
      if (shutterList.isNotEmpty && widget.model.hasShutter) {
        selectedShutter = shutterList.first;
      }
      if (jointList.isNotEmpty) selectedJoint = jointList.first;
      if (accessoryList.isNotEmpty) selectedAccessory = accessoryList.first;
      if (colorList.isNotEmpty) selectedColor = colorList.first;

      isLoading = false;
      _calculateCost();
    });
  }
"""

content = re.sub(r'  Future<void> _loadData\(\) async \{.*?\n  \}', robust_safe_load, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
