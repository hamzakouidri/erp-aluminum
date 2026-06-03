import re

file_path = "lib/Screen/price_management_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

safe_load = """
  Future<void> _loadAllData() async {
    final dbInstance = (await db.db)!;
    
    Future<List<Map<String, dynamic>>> safeQuery(String table) async {
      try {
        return await dbInstance.query(table);
      } catch (e) {
        print("Error loading $table: $e");
        // Ensure the table exists if it failed
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
        }
        return [];
      }
    }

    final sList = await safeQuery('Series');
    final cList = await safeQuery('Colors');
    final gList = await safeQuery('Glass');
    final shList = await safeQuery('Shutters');
    final aList = await safeQuery('Accessories');
    final jList = await safeQuery('Joints');

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
      colorList = cList;
      glassList = gList;
      shutterList = shList;
      accessoryList = aList;
      jointList = jList;
      seriesColorPrices = tempPrices;
      
      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }
      
      isLoading = false;
    });
  }
"""

content = re.sub(r'  Future<void> _loadAllData\(\) async \{.*?\n  \}', safe_load, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
