import re

file_path = "lib/Commande/Systeme/cost_summary_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# Replace the unsafe calculations
def safe_parse_code():
    return """
  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  void _calculateCost() {
    double cost = 0.0;

    // 1. Aluminum Cost (by linear meter)
    if (selectedSeries != null) {
      double priceMeter = _parsePrice(selectedSeries!['price_per_meter']);
      cost += totalAlumLength * priceMeter;
    }

    // 2. Glass Cost
    if (selectedGlass != null) {
      double pSq = _parsePrice(selectedGlass!['price_per_sqm']);
      cost += glassArea * pSq;
    }

    // 3. Shutter Cost
    if (widget.model.hasShutter && selectedShutter != null) {
      double pSq = _parsePrice(selectedShutter!['price_per_sqm']);
      cost += shutterArea * pSq;
    }

    // 4. Joint Cost
    if (selectedJoint != null) {
      double pM = _parsePrice(selectedJoint!['price_per_meter']);
      cost += jointPerimeter * pM;
    }

    // 5. Accessory Cost
    if (selectedAccessory != null) {
      double pAcc = _parsePrice(selectedAccessory!['price']);
      cost += pAcc;
    }

    // 6. Color Cost
    if (selectedColor != null) {
      double pColor = _parsePrice(selectedColor!['price']);
      cost += pColor;
    }

    setState(() {
      totalCost = cost;
    });
  }
"""

content = re.sub(r"void _calculateCost\(\) \{.*?(?=  @override)", safe_parse_code(), content, flags=re.DOTALL)

# Let's also fix the DropdownButtonFormField to have value: value
content = content.replace("initialValue: value,", "value: value,")

with open(file_path, "w", encoding="utf-8") as f:
    f.write(content)
