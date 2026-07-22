import re

f = r"lib\Commande\Systeme\material_consumption_screen.dart"

with open(f, 'r', encoding='utf-8') as file:
    content = file.read()

pattern = r"""final dbInstance = await db\.db;\s*// O U,OUO3O3U^O OO O\s*_dbAccessories = \(await db\.readAccessories\(\)\)\.map\(\(e\) => Map<String, dynamic>\.from\(\(e\)\)\)\.toList\(\);"""
replacement = """final dbInstance = await db.db;
    
    List<Map<String, dynamic>> shutterComps = [];
    try {
      shutterComps = await dbInstance!.query('ShutterComponents');
    } catch (_) {}
    
    double getSCPrice(String k1, [String? k2]) {
      try {
        return shutterComps.firstWhere((c) {
          String n = c['name'].toString().toLowerCase();
          return n.contains(k1.toLowerCase()) || (k2 != null && n.contains(k2.toLowerCase()));
        })['price'] as double;
      } catch (_) {
        return 0.0;
      }
    }

    // الإكسسوارات
    _dbAccessories = (await db.readAccessories()).map((e) => Map<String, dynamic>.from(e)).toList();"""

content = re.sub(pattern, replacement, content, flags=re.DOTALL)

pattern_add_shutter = r"""addShutterComponent\(\s*'O"O OO O O U,O'U?OO O \(Lames\)',\s*totalBarsNeeded,\s*'O"O OOc \(5\.8m\)',\s*0\.0,\s*\);"""
replacement_add_shutter = """addShutterComponent(
        'شفرات الستارة (Lames)',
        totalBarsNeeded,
        'بارة (5.8m)',
        getSCPrice('lame', 'شفر'),
      );"""
content = re.sub(pattern_add_shutter, replacement_add_shutter, content, flags=re.DOTALL)

# Let's replace the 0.0s with actual calls to getSCPrice using string replacement for the specific ones
content = content.replace("addShutterComponent(\n        'سيارة مجمعة (المساحة)',\n        shutterAreaSqm,\n        'متر مربع',\n        0.0,\n      );",
"addShutterComponent(\n        'ستارة مجمعة (المساحة)',\n        shutterAreaSqm,\n        'متر مربع',\n        getSCPrice('ستار', 'volet'),\n      );")

content = content.replace("addShutterComponent('كوليس', coulisseLengthM * 2, 'متر طولي', 0.0);",
"addShutterComponent('كوليس', coulisseLengthM * 2, 'متر طولي', getSCPrice('coulisse', 'كوليس'));")

content = content.replace("addShutterComponent('كيسون', wMeters, 'متر طولي', 0.0);",
"addShutterComponent('كيسون', wMeters, 'متر طولي', getSCPrice('caisson', 'كيسون'));")

content = content.replace("addShutterComponent(\n        'أكس (محور 40/60/70 ملم)',\n        (shutterWidthCm - 7.0) / 100.0,\n        'متر طولي',\n        0.0,\n      );",
"addShutterComponent(\n        'أكس (محور 40/60/70 ملم)',\n        (shutterWidthCm - 7.0) / 100.0,\n        'متر طولي',\n        getSCPrice('axe', 'محور'),\n      );")

content = content.replace("addShutterComponent(\n        'لام فينال',\n        slatCutLengthCm / 100.0,\n        'متر طولي',\n        0.0,\n      );",
"addShutterComponent(\n        'لام فينال',\n        slatCutLengthCm / 100.0,\n        'متر طولي',\n        getSCPrice('lame final', 'فينال'),\n      );")

content = content.replace("addShutterComponent(\n        'جوان بروس كوليس (Joint Brosse)',\n        (coulisseLengthM * 4),\n        'متر طولي',\n        0.0,\n      );",
"addShutterComponent(\n        'جوان بروس كوليس (Joint Brosse)',\n        (coulisseLengthM * 4),\n        'متر طولي',\n        getSCPrice('brosse', 'بروس'),\n      );")

content = content.replace("addShutterComponent(\n        'جوان مطاط لام فينال',\n        slatCutLengthCm / 100.0,\n        'متر طولي',\n        0.0,\n      );",
"addShutterComponent(\n        'جوان مطاط لام فينال',\n        slatCutLengthCm / 100.0,\n        'متر طولي',\n        getSCPrice('joint', 'جوان'),\n      );")

content = content.replace("addShutterComponent('ميكانيزم (محرك/مانيفال/سانغل)', 1.0, 'وحدة', 0.0);",
"addShutterComponent('ميكانيزم (محرك/مانيفال/سانغل)', 1.0, 'وحدة', getSCPrice('moteur', 'محرك'));")

with open(f, 'w', encoding='utf-8') as file:
    file.write(content)

print("Shutter component prices updated.")
