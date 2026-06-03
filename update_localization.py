import sys

with open('lib/settings/localization.dart', 'r', encoding='utf-8') as f:
    content = f.read()

new_translations_en = '''    AppLanguage.en: {
      // Colors
      "White": "White",
      "Dark Grey": "Dark Grey",
      "Light Grey": "Light Grey",
      "Black": "Black",
      "Wood": "Wood",
      "Silver": "Silver",
      "Champagne": "Champagne",
      "Bronze": "Bronze",
      "Beige": "Beige",
      
      // Accessories
      "Material Type": "Material Type",
      "Scope": "Scope",
      "Global": "Global",
      "Unique (Per Series)": "Unique (Per Series)",
      "Series": "Series",
      
      // Sections
      "Sections Pricing": "Sections Pricing",
      "Section Price": "Section Price",'''

new_translations_ar = '''    AppLanguage.ar: {
      // Colors
      "White": "أبيض",
      "Dark Grey": "رمادي داكن",
      "Light Grey": "رمادي فاتح",
      "Black": "أسود",
      "Wood": "خشبي",
      "Silver": "فضي",
      "Champagne": "شامبانيا",
      "Bronze": "برونزي",
      "Beige": "بيج",
      
      // Accessories
      "Material Type": "نوع المادة",
      "Scope": "النطاق",
      "Global": "عام",
      "Unique (Per Series)": "خاص بسلسلة",
      "Series": "السلسلة",
      
      // Sections
      "Sections Pricing": "تسعير المقاطع",
      "Section Price": "سعر المقطع",'''

new_translations_fr = '''    AppLanguage.fr: {
      // Colors
      "White": "Blanc",
      "Dark Grey": "Gris Foncé",
      "Light Grey": "Gris Clair",
      "Black": "Noir",
      "Wood": "Faux Bois",
      "Silver": "Argenté",
      "Champagne": "Champagne",
      "Bronze": "Bronze",
      "Beige": "Beige",
      
      // Accessories
      "Material Type": "Type de Matériau",
      "Scope": "Portée",
      "Global": "Global",
      "Unique (Per Series)": "Unique (Par Série)",
      "Series": "Série",
      
      // Sections
      "Sections Pricing": "Prix des Profilés",
      "Section Price": "Prix du Profilé",'''

content = content.replace('    AppLanguage.en: {', new_translations_en)
content = content.replace('    AppLanguage.ar: {', new_translations_ar)
content = content.replace('    AppLanguage.fr: {', new_translations_fr)

with open('lib/settings/localization.dart', 'w', encoding='utf-8') as f:
    f.write(content)
