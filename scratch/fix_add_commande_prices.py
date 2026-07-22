import re

f = r"lib\Commande\add_commande.dart"

with open(f, 'r', encoding='utf-8') as file:
    content = file.read()

# 1. Add SizedBox to _showReportBottomSheet
content = content.replace("const SizedBox(height: 20),\n                  SizedBox(\n                    width: double.infinity,\n                    child: ElevatedButton(", "const SizedBox(height: 120),\n                  SizedBox(\n                    width: double.infinity,\n                    child: ElevatedButton(")

# 2. Fix the hardcoded prices in _calculateGlobalMaterialsAndCost
# Find the calculation of grandTotal
grand_total_calc = """    double grandTotal = (totalAluminumMeters * priceAlumPerMeter) +
        (totalGlassSqm * priceGlassPerSqm) +
        (totalHandles * priceHandle) +
        (totalHinges * priceHinge) +
        (totalRoulettes * priceRoulette) +
        (totalShutterLamesMeters * priceLamesPerMeter) +
        (totalShutters * priceShutterKit);"""

replacement = """    double grandTotal = addedProducts.fold(
      0.0,
      (sum, p) => sum + ((p.manualPriceOverride ?? p.totalCost) * p.quantity),
    );"""

content = content.replace(grand_total_calc, replacement)

with open(f, 'w', encoding='utf-8') as file:
    file.write(content)
print("Done add_commande.dart")


f2 = r"lib\Commande\Systeme\material_consumption_screen.dart"
with open(f2, 'r', encoding='utf-8') as file:
    content2 = file.read()

content2 = content2.replace("const SizedBox(height: 80), // Padding for bottom bar", "const SizedBox(height: 180), // Padding for bottom bar")
with open(f2, 'w', encoding='utf-8') as file:
    file.write(content2)
print("Done material_consumption_screen.dart")

f3 = r"lib\Commande\Systeme\cost_summary_screen.dart"
with open(f3, 'r', encoding='utf-8') as file:
    content3 = file.read()

content3 = content3.replace("            SizedBox(height: 20),\n\n            // OO OO O U?Oc O U,OU,O\"", "            SizedBox(height: 120),\n\n            // OO OO O U?Oc O U,OU,O\"")
with open(f3, 'w', encoding='utf-8') as file:
    file.write(content3)
print("Done cost_summary_screen.dart")

