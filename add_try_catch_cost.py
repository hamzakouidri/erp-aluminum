import re

file_path = "lib/Commande/Systeme/cost_summary_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

safe_load = """
  Future<void> _loadData() async {
    try {
      final dbInstance = (await db.db)!;
      final sList = await dbInstance.query('Series');
      final gList = await dbInstance.query('Glass');
      final shList = await dbInstance.query('Shutters');
      final jList = await dbInstance.query('Joints');
      final aList = await dbInstance.query('Accessories');
      final cList = await dbInstance.query('Colors');

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
    } catch (e) {
      print("Error loading cost data: $e");
      if (mounted) {
        setState(() {
          isLoading = false;
        });
      }
    }
  }
"""

content = re.sub(r'  Future<void> _loadData\(\) async \{.*?\n  \}', safe_load, content, flags=re.DOTALL)

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
