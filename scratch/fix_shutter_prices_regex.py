import re

f = r"lib\Commande\Systeme\material_consumption_screen.dart"

with open(f, 'r', encoding='utf-8') as file:
    content = file.read()

# Instead of exact match, just use regex to replace the 0.0 in addShutterComponent calls.
# addShutterComponent('...', var, '...', 0.0);

def replacer(match):
    name = match.group(1)
    if 'Lames' in name or 'lame' in name.lower() or 'شفر' in name:
        price_call = "getSCPrice('lame', 'شفر')"
    elif 'مجمعة' in name or 'ستارة' in name or 'volet' in name.lower():
        price_call = "getSCPrice('volet', 'ستار')"
    elif 'coulisse' in name.lower() or 'كوليس' in name:
        if 'Joint' in name or 'brosse' in name.lower() or 'جوان' in name:
            price_call = "getSCPrice('brosse', 'بروس')"
        else:
            price_call = "getSCPrice('coulisse', 'كوليس')"
    elif 'caisson' in name.lower() or 'كيسون' in name:
        price_call = "getSCPrice('caisson', 'كيسون')"
    elif 'axe' in name.lower() or 'محور' in name or 'أكس' in name:
        price_call = "getSCPrice('axe', 'محور')"
    elif 'final' in name.lower() or 'فينال' in name:
        if 'joint' in name.lower() or 'جوان' in name or 'مطاط' in name:
            price_call = "getSCPrice('joint', 'جوان')"
        else:
            price_call = "getSCPrice('lame final', 'فينال')"
    elif 'moteur' in name.lower() or 'محرك' in name or 'ميكانيزم' in name:
        price_call = "getSCPrice('moteur', 'محرك')"
    else:
        price_call = "0.0"
        
    return f"addShutterComponent({match.group(1)}, {match.group(2)}, {match.group(3)}, {price_call})"

pattern = r"addShutterComponent\(([^,]+),\s*([^,]+),\s*([^,]+),\s*0\.0\s*\)"
content = re.sub(pattern, replacer, content)

with open(f, 'w', encoding='utf-8') as file:
    file.write(content)

print("Shutter component prices updated via regex.")
