import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

replacements = {
    'شفاف': {'fr': 'Clair', 'en': 'Clear'},
    'ستوبسول': {'fr': 'Stopsol', 'en': 'Stopsol'},
    'صابلي': {'fr': 'Sabler', 'en': 'Frosted'},
    'دلتا': {'fr': 'Delta', 'en': 'Delta'},
    'تيسي': {'fr': 'Martelé', 'en': 'Patterned'},
    'نيفادا': {'fr': 'Nevada', 'en': 'Nevada'},
    'مطبخ': {'fr': 'Cuisine', 'en': 'Kitchen'},
    'مورد': {'fr': 'À fleurs', 'en': 'Floral'},
    'ارزين': {'fr': 'Résine', 'en': 'Resin'},
    'بانو ديكور': {'fr': 'Panneau Décoré', 'en': 'Decorated Panel'},
    'بارداش': {'fr': 'Bardage', 'en': 'Siding'},
    'حراري': {'fr': 'Thermique', 'en': 'Tempered'},
    'رمادي بلجيكي': {'fr': 'Gris Belge', 'en': 'Belgian Grey'},
    'ازرق بلجيكي': {'fr': 'Bleu Belge', 'en': 'Belgian Blue'},
    'ابيض': {'fr': 'Blanc', 'en': 'White'},
    'اسود': {'fr': 'Noir', 'en': 'Black'},
    'باج': {'fr': 'Beige', 'en': 'Beige'},
    'خشبي داكن': {'fr': 'Bois Foncé', 'en': 'Dark Wood'},
    'خشبي فاتح': {'fr': 'Bois Clair', 'en': 'Light Wood'},
    'عاتم': {'fr': 'Opaque', 'en': 'Opaque'},
}

new_keys = {
    'الكمية والتكلفة': {'ar': 'الكمية والتكلفة', 'fr': 'Quantité et Coût', 'en': 'Quantity and Cost'},
    'الالكمية والتكلفة': {'ar': 'الكمية والتكلفة', 'fr': 'Quantité et Coût', 'en': 'Quantity and Cost'},
    'القياس': {'ar': 'القياس', 'fr': 'Dimensions / Mesures', 'en': 'Dimensions / Measurement'},
    'إعدادات السعر': {'ar': 'إعدادات السعر', 'fr': 'Paramètres de prix', 'en': 'Price Settings'},
    'تفاصيل الحساب': {'ar': 'تفاصيل الحساب', 'fr': 'Détails du compte', 'en': 'Account Details'},
    'قطعة': {'ar': 'قطعة', 'fr': 'Pièce', 'en': 'Piece'},
    'حبة': {'ar': 'حبة', 'fr': 'Unité', 'en': 'Unit'},
    'متر': {'ar': 'متر', 'fr': 'Mètre', 'en': 'Meter'},
    'سعر التكلفة الإجمالي': {'ar': 'سعر التكلفة الإجمالي', 'fr': 'Prix de revient total', 'en': 'Total Cost Price'},
    'سعر القطعة': {'ar': 'سعر القطعة', 'fr': 'Prix unitaire', 'en': 'Piece Price'},
    'جدول السلع': {'ar': 'جدول السلع', 'fr': 'Tableau des marchandises', 'en': 'Goods Table'},
    'مراسلة الإدارة': {'ar': 'مراسلة الإدارة', 'fr': 'Contacter l\'administration', 'en': 'Contact Admin'},
    'المخزون': {'ar': 'المخزون', 'fr': 'Stock', 'en': 'Stock'},
    'الموردين': {'ar': 'الموردين', 'fr': 'Fournisseurs', 'en': 'Suppliers'},
    'المشتريات': {'ar': 'المشتريات', 'fr': 'Achats', 'en': 'Purchases'},
    'البروفيلات': {'ar': 'البروفيلات', 'fr': 'Profilés', 'en': 'Profiles'},
    'ستوب صول': {'ar': 'ستوب صول', 'fr': 'Stopsol', 'en': 'Stopsol'},
    'مركبات الستار': {'ar': 'مركبات الستار', 'fr': 'Composants de volet', 'en': 'Shutter Components'},
    'ألوانات': {'ar': 'ألوانات', 'fr': 'Couleurs', 'en': 'Colors'},
    'الكيت': {'ar': 'الكيت', 'fr': 'Kits', 'en': 'Kits'},
    'بليكسي': {'ar': 'بليكسي', 'fr': 'Plexiglas', 'en': 'Plexiglass'},
    'موسى': {'ar': 'موسى', 'fr': 'Moussa', 'en': 'Moussa'},
    'زجاج مسلح': {'ar': 'زجاج مسلح', 'fr': 'Verre armé', 'en': 'Wired Glass'},
    'رخامي': {'ar': 'رخامي', 'fr': 'Marbré', 'en': 'Marbled'},
}

# 1. Perform replacements
for term, trans in replacements.items():
    # Regex to find:
    # 'term': {
    #   AppLanguage.arabic: 'term',
    #   AppLanguage.french: '...',
    #   AppLanguage.english: '...',
    # }
    pattern = rf"('{term}':\s*\{{\s*AppLanguage\.arabic:\s*['\"].*?['\"],\s*AppLanguage\.french:\s*['\"]).*?(['\"],\s*AppLanguage\.english:\s*['\"]).*?(['\"],\s*\}})"
    
    # We replace french and english contents
    replacement = rf"\g<1>{trans['fr']}\g<2>{trans['en']}\g<3>"
    content, count = re.subn(pattern, replacement, content, flags=re.DOTALL)
    if count > 0:
        print(f"Replaced translations for '{term}' successfully.")
    else:
        # try double quotes
        pattern_double = rf"(\"{term}\":\s*\{{\s*AppLanguage\.arabic:\s*['\"].*?['\"],\s*AppLanguage\.french:\s*['\"]).*?(['\"],\s*AppLanguage\.english:\s*['\"]).*?(['\"],\s*\}})"
        content, count = re.subn(pattern_double, replacement, content, flags=re.DOTALL)
        if count > 0:
            print(f"Replaced translations for \"{term}\" successfully.")
        else:
            # If not found, add it as a new key
            new_keys[term] = {'ar': term, 'fr': trans['fr'], 'en': trans['en']}

# 2. Append new keys at the end of the map (before the trailing };)
new_entries = []
for term, trans in new_keys.items():
    entry = f"""  '{term}': {{
    AppLanguage.arabic: '{trans['ar']}',
    AppLanguage.french: '{trans['fr']}',
    AppLanguage.english: '{trans['en']}',
  }},"""
    new_entries.append(entry)

new_entries_str = "\n".join(new_entries)
content = content.replace("};", new_entries_str + "\n};")
print(f"Appended {len(new_keys)} new keys.")

open(path, 'w', encoding='utf-8').write(content)
print("Done updating general_keys.dart!")
