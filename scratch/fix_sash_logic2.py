import re

files = [
    r"lib\Commande\Systeme\cost_summary_screen.dart",
    r"lib\Commande\Systeme\material_consumption_screen.dart"
]

def fix_cost_summary(content):
    pattern = r"""\s*double getSashPrice\(bool is105\) \{.*?(?=\s*double framePrice = getSecPrice\('frame'\);)"""
    replacement = """
      double getSashPrice(bool is105) {
         if (widget.model.activeSeries != null) {
            var secs = widget.model.activeSeries!.sections.where((s) => s.type == 'sash' || s.type == 'sash_104' || s.type == 'sash_105' || s.name.toLowerCase().contains('ضلفة') || s.name.toLowerCase().contains('sash') || s.name.toLowerCase().contains('ouvrant')).toList();
            if (secs.isNotEmpty) {
               int targetId = -1;
               if (is105) {
                  try { targetId = secs.firstWhere((s) => s.type == 'sash_105' || s.name.contains('105') || s.code.contains('105') || s.name.contains('كبير')).id; } catch(_) { targetId = secs.length > 1 ? secs[1].id : secs.first.id; }
               } else {
                  try { targetId = secs.firstWhere((s) => s.type == 'sash_104' || s.name.contains('104') || s.code.contains('104') || s.name.contains('صغير')).id; } catch(_) { targetId = secs.first.id; }
               }
               if (sectionColorPrices.containsKey(targetId)) {
                  if (colorId != -1 && sectionColorPrices[targetId]!.containsKey(colorId)) {
                     double p = sectionColorPrices[targetId]![colorId]!;
                     if (p > 0) return p;
                  }
                  for (var p in sectionColorPrices[targetId]!.values) {
                     if (p > 0) return p;
                  }
               }
            }
         }
         return 0.0;
      }
"""
    return re.sub(pattern, replacement, content, flags=re.DOTALL)

def fix_material_consumption(content):
    pattern = r"""var sashes = widget\.model\.activeSeries!\.sections\.where\(\(s\) => s\.type == 'sash' \|\| s\.name\.toLowerCase\(\)\.contains\('.*?'\) \|\| s\.name\.toLowerCase\(\)\.contains\('.*?'\)\)\.toList\(\);\s*if \(sashes\.isNotEmpty\) \{\s*bool has105 = widget\.model\.zones\.any\(\(z\) => z\.isSash105\);\s*if \(has105\) \{\s*try \{ sashSecId = sashes\.firstWhere\(\(s\) => s\.name\.contains\('105'\) \|\| s\.code\.contains\('105'\)\)\.id; \} catch \(_\) \{ sashSecId = \(sashes\.length > 1\) \? sashes\[1\]\.id : sashes\.first\.id; \}\s*\} else \{\s*try \{ sashSecId = sashes\.firstWhere\(\(s\) => s\.name\.contains\('104'\) \|\| s\.code\.contains\('104'\)\)\.id; \} catch \(_\) \{ sashSecId = sashes\.first\.id; \}\s*\}\s*\}"""
    replacement = """var sashes = widget.model.activeSeries!.sections.where((s) => s.type == 'sash' || s.type == 'sash_104' || s.type == 'sash_105' || s.name.toLowerCase().contains('ضلفة') || s.name.toLowerCase().contains('ouvrant')).toList();
          if (sashes.isNotEmpty) {
             bool has105 = widget.model.zones.any((z) => z.isSash105);
             if (has105) {
               try { sashSecId = sashes.firstWhere((s) => s.type == 'sash_105' || s.name.contains('105') || s.code.contains('105') || s.name.contains('كبير')).id; } catch (_) { sashSecId = (sashes.length > 1) ? sashes[1].id : sashes.first.id; }
             } else {
               try { sashSecId = sashes.firstWhere((s) => s.type == 'sash_104' || s.name.contains('104') || s.code.contains('104') || s.name.contains('صغير')).id; } catch (_) { sashSecId = sashes.first.id; }
             }
          }"""
    return re.sub(pattern, replacement, content, flags=re.DOTALL)

for f in files:
    with open(f, 'r', encoding='utf-8') as file:
        content = file.read()
    
    if "cost_summary_screen.dart" in f:
        content = fix_cost_summary(content)
    else:
        content = fix_material_consumption(content)
        
    with open(f, 'w', encoding='utf-8') as file:
        file.write(content)

print("Done replacing sash logic.")
