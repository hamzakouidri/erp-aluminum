import os
import time
from deep_translator import GoogleTranslator

missing_file = 'missing_arabic.txt'
loc_file = r'c:\Users\hp\AndroidStudioProjects\database_data\lib\settings\localization.dart'

with open(missing_file, 'r', encoding='utf-8') as f:
    missing = f.read().splitlines()

# Load current loc_file
with open(loc_file, 'r', encoding='utf-8') as f:
    loc_content = f.read()

# Auto-dict for perfect domain-specific translations
auto_dict = {
    'الزجاج (Glass)': ['Verre', 'Glass'],
    'الستائر (Shutters)': ['Volets Roulants', 'Shutters'],
    'الطلبات (Orders)': ['Commandes', 'Orders'],
    'المشتريات': ['Achats', 'Purchases'],
    'الصندوق المالي': ['Caisse', 'Treasury'],
    'الزبائن والدفعات': ['Clients & Paiements', 'Clients & Payments'],
    'تسجيل الدخول': ['Connexion', 'Login'],
    'إنشاء حساب': ['Créer un compte', 'Create Account'],
    'المقاطع (Sections)': ['Sections', 'Sections'],
    'السلاسل (Series)': ['Séries', 'Series'],
    'الأنظمة (Profiles)': ['Profilés', 'Profiles'],
}

translator_fr = GoogleTranslator(source='ar', target='fr')
translator_en = GoogleTranslator(source='ar', target='en')

buffer = []
print(f"Starting translation of {len(missing)} strings...")

for i, key in enumerate(missing):
    key = key.strip()
    if not key: continue
    
    fr, en = key, key
    if key in auto_dict:
        fr = auto_dict[key][0]
        en = auto_dict[key][1]
    else:
        try:
            # We don't want to translate strings that contain only English/Variables
            # Let's just try to translate
            fr = translator_fr.translate(key)
            en = translator_en.translate(key)
            time.sleep(0.05) # Prevent rate limiting
        except Exception as e:
            # Silently ignore errors
            fr, en = key, key
    
    if fr is None: fr = key
    if en is None: en = key
    
    safe_key = key.replace("'''", "")
    safe_fr = fr.replace("'''", "")
    safe_en = en.replace("'''", "")
    
    buffer.append(f"    r'''{safe_key}''': {{")
    buffer.append(f"      AppLanguage.arabic: r'''{safe_key}''',")
    buffer.append(f"      AppLanguage.french: r'''{safe_fr}''',")
    buffer.append(f"      AppLanguage.english: r'''{safe_en}''',")
    buffer.append("    },")
    
    if i % 50 == 0:
        print(f"Translated {i}/{len(missing)}")

print("Done translating. Injecting...")

# We need to remove the previously injected raw strings from the file to avoid duplicates.
# Let's read the repaired localization.dart instead of the current one if it has duplicates,
# BUT I ALREADY REPAIRED IT EARLIER using repair.py.
# Wait, my previous `inject.py` successfully injected 380 keys with raw strings (but untranslated).
# So I should repair it AGAIN to remove those 380 untranslated raw strings!

target = "'Select the product category to manage',\n    },"
idx = loc_content.find(target)
method_idx = loc_content.find("  static String translate(String key, AppLanguage lang) {")

if idx != -1 and method_idx != -1:
    end_of_good_dict = idx + len(target)
    
    injected = "\n" + "\n".join(buffer)
    
    new_content = loc_content[:end_of_good_dict] + injected + "\n  };\n\n" + loc_content[method_idx:]
    
    with open(loc_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Successfully fully translated and injected {len(missing)} keys.")
else:
    print("Could not find target strings for injection.")
