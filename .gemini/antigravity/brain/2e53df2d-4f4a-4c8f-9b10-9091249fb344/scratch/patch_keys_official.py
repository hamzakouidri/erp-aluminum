import re

path_keys = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\settings\locales\general_keys.dart'

with open(path_keys, 'r', encoding='utf-8') as f:
    code = f.read()

ANCHOR_KEY = """  'caisse': {"""
NEW_KEYS = """  'فاتورة رسمية / أولية': {
    AppLanguage.arabic: 'فاتورة رسمية / أولية',
    AppLanguage.french: 'Facture Proforma / Officielle',
    AppLanguage.english: 'Proforma / Official Invoice',
  },
  'فاتورة رسمية / أولية بدون أسعار': {
    AppLanguage.arabic: 'فاتورة رسمية / أولية بدون أسعار',
    AppLanguage.french: 'Facture Proforma / Officielle sans prix',
    AppLanguage.english: 'Proforma / Official Invoice without prices',
  },
  'caisse': {"""

assert ANCHOR_KEY in code, "Anchor key not found in general_keys.dart"
code = code.replace(ANCHOR_KEY, NEW_KEYS, 1)

with open(path_keys, 'w', encoding='utf-8') as f:
    f.write(code)
print("general_keys.dart updated successfully.")
