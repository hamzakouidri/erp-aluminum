import re

file_path = "lib/Commande/Systeme/cost_summary_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Add seriesColorPrices map
if "Map<int, Map<int, double>> seriesColorPrices = {};" not in content:
    content = content.replace(
        "List<Map<String, dynamic>> colorList = [];",
        "List<Map<String, dynamic>> colorList = [];\n  Map<int, Map<int, double>> seriesColorPrices = {};"
    )

# Load seriesColorPrices in _loadData()
load_prices_code = """
    final pricesData = await dbInstance.query('SeriesColorPrices');
    Map<int, Map<int, double>> tempPrices = {};
    for (var row in pricesData) {
      int sId = row['series_id'] as int;
      int cId = row['color_id'] as int;
      double p = (row['price'] as num).toDouble();
      if (!tempPrices.containsKey(sId)) {
        tempPrices[sId] = {};
      }
      tempPrices[sId]![cId] = p;
    }
"""
if "final pricesData" not in content:
    content = content.replace(
        "final cList = await dbInstance.query('Colors');",
        "final cList = await dbInstance.query('Colors');\n" + load_prices_code
    )

    content = content.replace(
        "colorList = cList;",
        "colorList = cList;\n      seriesColorPrices = tempPrices;"
    )

# Update _calculateCost() to use seriesColorPrices
calc_cost_original = """    // 1. Aluminum Cost (by linear meter)
    if (selectedSeries != null) {
      double priceMeter = _parsePrice(selectedSeries!['price_per_meter']);
      cost += totalAlumLength * priceMeter;
    }"""

calc_cost_new = """    // 1. Aluminum Cost (by linear meter using SeriesColorPrices)
    if (selectedSeries != null) {
      double priceMeter = 0.0;
      if (selectedColor != null && seriesColorPrices.containsKey(selectedSeries!['id'])) {
        priceMeter = seriesColorPrices[selectedSeries!['id']]?[selectedColor!['id']] ?? 0.0;
      }
      // Fallback to series default if no specific color price
      if (priceMeter == 0.0) {
        priceMeter = _parsePrice(selectedSeries!['price_per_meter']);
      }
      cost += totalAlumLength * priceMeter;
    }"""

content = content.replace(calc_cost_original, calc_cost_new)

# Update Color Cost since Color Price is now included in Series, we don't add it separately if we don't want to. 
# But the original code adds color cost separately.
color_cost_original = """    // 6. Color Cost (Extra per meter)
    if (selectedColor != null) {
      double pColor = _parsePrice(selectedColor!['price']);
      cost += totalAlumLength * pColor;
    }"""

# We can remove the Extra per meter color cost, or keep it as an optional generic addition.
# It's better to remove it because the user explicitly wants Series+Color intersection price.
content = content.replace(color_cost_original, """    // 6. Color Cost is now handled in Series Color Prices""")

# Ensure dropdown updates calculation
# When Dropdown changes, _calculateCost() is called.
# It's already done because `onChanged: (val) { setState(() { selected... = val; _calculateCost(); }); }`

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
