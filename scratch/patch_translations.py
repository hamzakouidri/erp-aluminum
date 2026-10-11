with open('lib/settings/locales/general_keys.dart', 'r', encoding='utf-8') as f:
    content = f.read()

target = "  'المستودع (إضافة للفاتورة)': {"
addition = """  'المستودع - إضافة عناصر للفاتورة (اسحب للتحريك)': {
    AppLanguage.arabic: 'المستودع - إضافة عناصر للفاتورة (اسحب للتحريك)',
    AppLanguage.french: 'Dépôt - Ajouter des articles à la facture (Glisser pour déplacer)',
    AppLanguage.english: 'Warehouse - Add items to invoice (Drag to move)',
  },
  'إضافة عناصر (مصغرة)': {
    AppLanguage.arabic: 'إضافة عناصر (مصغرة)',
    AppLanguage.french: 'Ajouter des articles (Minimisé)',
    AppLanguage.english: 'Add items (Minimized)',
  },
  'السعر: --': {
    AppLanguage.arabic: 'السعر: --',
    AppLanguage.french: 'Prix : --',
    AppLanguage.english: 'Price: --',
  },
"""

if target in content:
    content = content.replace(target, addition + target, 1)
    with open('lib/settings/locales/general_keys.dart', 'w', encoding='utf-8', newline='') as f:
        f.write(content)
    print('SUCCESS')
else:
    print('NOT FOUND')
