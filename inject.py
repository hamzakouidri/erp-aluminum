import os
import json

missing_file = 'missing_arabic.txt'
loc_file = r'c:\Users\hp\AndroidStudioProjects\database_data\lib\settings\localization.dart'

with open(missing_file, 'r', encoding='utf-8') as f:
    missing = f.read().splitlines()
    
with open(loc_file, 'r', encoding='utf-8') as f:
    loc_content = f.read()

# Auto-translate dict
auto_dict = {
    'الزجاج (Glass)': ['Verre', 'Glass'],
    'الستائر (Shutters)': ['Volets Roulants', 'Shutters'],
    'الطلبات (Orders)': ['Commandes', 'Orders'],
    'المشتريات': ['Achats', 'Purchases'],
    'الصندوق المالي': ['Caisse', 'Treasury'],
    'الزبائن والدفعات': ['Clients & Paiements', 'Clients & Payments'],
    'تسجيل الدخول': ['Connexion', 'Login'],
    'إنشاء حساب': ['Créer un compte', 'Create Account'],
}

buffer = []
for key in missing:
    key = key.strip()
    if not key: continue
    
    fr = key
    en = key
    if 'إضافة' in key: fr = 'Ajouter'; en = 'Add'
    elif 'تعديل' in key: fr = 'Modifier'; en = 'Edit'
    elif 'حذف' in key: fr = 'Supprimer'; en = 'Delete'
    elif 'اسم' in key: fr = 'Nom'; en = 'Name'
    elif 'سعر' in key: fr = 'Prix'; en = 'Price'
    elif 'نوع' in key: fr = 'Type'; en = 'Type'
    
    if key in auto_dict:
        fr = auto_dict[key][0]
        en = auto_dict[key][1]
        
    # Use Dart raw strings r'''...''' so that $ is not evaluated
    # Escape any single quotes inside the string if necessary, but r''' can contain them unless it's '''
    safe_key = key.replace("'''", "")
    safe_fr = fr.replace("'''", "")
    safe_en = en.replace("'''", "")
    
    buffer.append(f"    r'''{safe_key}''': {{")
    buffer.append(f"      AppLanguage.arabic: r'''{safe_key}''',")
    buffer.append(f"      AppLanguage.french: r'''{safe_fr}''',")
    buffer.append(f"      AppLanguage.english: r'''{safe_en}''',")
    buffer.append("    },")

target = "'Select the product category to manage',\n    },"

idx = loc_content.find(target)
if idx != -1:
    end_of_good_dict = idx + len(target)
    
    injected = "\n" + "\n".join(buffer)
    
    method_idx = loc_content.find("  static String translate(String key, AppLanguage lang) {")
    
    new_content = loc_content[:end_of_good_dict] + injected + "\n  };\n\n" + loc_content[method_idx:]
    
    with open(loc_file, 'w', encoding='utf-8') as f:
        f.write(new_content)
    print(f"Successfully injected {len(missing)} keys with raw strings.")
else:
    print("Could not find target good dictionary end")

