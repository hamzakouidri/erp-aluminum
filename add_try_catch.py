import re

file_path = "lib/Screen/price_management_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add try catch to loadAllData
safe_load = """
  Future<void> _loadAllData() async {
    try {
      final dbInstance = (await db.db)!;
      final sList = await dbInstance.query('Series');
      final cList = await dbInstance.query('Colors');
      final gList = await dbInstance.query('Glass');
      final shList = await dbInstance.query('Shutters');
      final aList = await dbInstance.query('Accessories');
      final jList = await dbInstance.query('Joints');

      Map<int, Map<int, double>> tempPrices = {};
      try {
        final pricesData = await dbInstance.query('SeriesColorPrices');
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
        print("Error loading SeriesColorPrices: $e");
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
    } catch (e) {
      print("Error loading data: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
"""

# replace the old method
content = re.sub(r'  Future<void> _loadAllData\(\) async \{.*?\n  \}', safe_load, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
