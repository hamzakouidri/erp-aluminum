import re

path_preview = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\devis_preview_screen.dart'
path_keys = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\settings\locales\general_keys.dart'

# ────────────────────────────────────────────────────
# 1. Update devis_preview_screen.dart
# ────────────────────────────────────────────────────
with open(path_preview, 'r', encoding='utf-8') as f:
    code_preview = f.read()

OLD_SAVE_BUTTON = """                onPressed: () => _savePdf(context),
                icon: const Icon(Icons.save, size: 16),
                label: Text(
                  'Save',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),"""

NEW_SAVE_BUTTON = """                onPressed: () => _savePdf(context),
                icon: const Icon(Icons.save, size: 16),
                label: Text(
                  t('حفظ'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
                ),"""

assert OLD_SAVE_BUTTON in code_preview, "Save button not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_SAVE_BUTTON, NEW_SAVE_BUTTON, 1)

OLD_SHARE_BUTTON = """                onPressed: () => _sharePdf(context),
                icon: const Icon(Icons.share, size: 16),
                label: Text(
                  'Share',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),"""

NEW_SHARE_BUTTON = """                onPressed: () => _sharePdf(context),
                icon: const Icon(Icons.share, size: 16),
                label: Text(
                  t('مشاركة'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
                ),"""

assert OLD_SHARE_BUTTON in code_preview, "Share button not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_SHARE_BUTTON, NEW_SHARE_BUTTON, 1)

OLD_PRINT_BUTTON = """                onPressed: () => _printPdf(context),
                icon: const Icon(Icons.print, size: 16),
                label: Text(
                  'Print',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
                ),"""

NEW_PRINT_BUTTON = """                onPressed: () => _printPdf(context),
                icon: const Icon(Icons.print, size: 16),
                label: Text(
                  t('طباعة'),
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12, fontFamily: 'Cairo'),
                ),"""

assert OLD_PRINT_BUTTON in code_preview, "Print button not found in devis_preview_screen"
code_preview = code_preview.replace(OLD_PRINT_BUTTON, NEW_PRINT_BUTTON, 1)

with open(path_preview, 'w', encoding='utf-8') as f:
    f.write(code_preview)
print("devis_preview_screen.dart updated successfully.")

# ────────────────────────────────────────────────────
# 2. Update general_keys.dart
# ────────────────────────────────────────────────────
with open(path_keys, 'r', encoding='utf-8') as f:
    code_keys = f.read()

ANCHOR_KEY = """  'caisse': {"""
NEW_KEYS = """  'مشاركة': {
    AppLanguage.arabic: 'مشاركة',
    AppLanguage.french: 'Partager',
    AppLanguage.english: 'Share',
  },
  'طباعة': {
    AppLanguage.arabic: 'طباعة',
    AppLanguage.french: 'Imprimer',
    AppLanguage.english: 'Print',
  },
  'caisse': {"""

assert ANCHOR_KEY in code_keys, "Anchor key not found in general_keys.dart"
code_keys = code_keys.replace(ANCHOR_KEY, NEW_KEYS, 1)

with open(path_keys, 'w', encoding='utf-8') as f:
    f.write(code_keys)
print("general_keys.dart updated successfully.")
