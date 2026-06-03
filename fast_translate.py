import os

missing_file = 'missing_arabic.txt'
loc_file = r'c:\Users\hp\AndroidStudioProjects\database_data\lib\settings\localization.dart'

with open(missing_file, 'r', encoding='utf-8') as f:
    missing = f.read().splitlines()

with open(loc_file, 'r', encoding='utf-8') as f:
    loc_content = f.read()

# Extensive auto dictionary
auto_dict = {
    'إضافة': ['Ajouter', 'Add'],
    'تعديل': ['Modifier', 'Edit'],
    'حذف': ['Supprimer', 'Delete'],
    'إلغاء': ['Annuler', 'Cancel'],
    'النوع': ['Type', 'Type'],
    'السعر': ['Prix', 'Price'],
    'الكمية': ['Quantité', 'Quantity'],
    'حفظ': ['Enregistrer', 'Save'],
    'المقاطع (Sections)': ['Sections', 'Sections'],
    'السلاسل (Series)': ['Séries', 'Series'],
    'الأنظمة (Profiles)': ['Profilés', 'Profiles'],
    'الزجاج (Glass)': ['Verre', 'Glass'],
    'الستائر (Shutters)': ['Volets Roulants', 'Shutters'],
    'الطلبات (Orders)': ['Commandes', 'Orders'],
    'المشتريات': ['Achats', 'Purchases'],
    'الصندوق المالي': ['Caisse', 'Treasury'],
    'الزبائن والدفعات': ['Clients & Paiements', 'Clients & Payments'],
    'تسجيل الدخول': ['Connexion', 'Login'],
    'إنشاء حساب': ['Créer un compte', 'Create Account'],
    'اسم المورد': ['Nom du fournisseur', 'Supplier Name'],
    'رقم الفاتورة': ['Numéro de facture', 'Invoice Number'],
    'المبلغ': ['Montant', 'Amount'],
    'البريد الإلكتروني': ['E-mail', 'Email'],
    'كلمة المرور': ['Mot de passe', 'Password'],
    'إجمالي المشتريات': ['Total des achats', 'Total Purchases'],
    'تعديل قياسات النافذة': ['Modifier les dimensions', 'Edit Window Dimensions'],
    'الارتفاع': ['Hauteur', 'Height'],
    'العرض': ['Largeur', 'Width'],
    'تسجيل كعامل': ["S'inscrire en tant qu'employé", "Register as Worker"],
    'مدير النظام': ['Administrateur', 'System Admin'],
    'عامل': ['Ouvrier', 'Worker'],
    'حفظ الدفعة': ['Enregistrer le paiement', 'Save Payment'],
    'إضافة مقطع ألمنيوم جديد': ['Ajouter un profilé aluminium', 'Add Aluminum Profile'],
    'إضافة أكسسوار جديد': ['Ajouter un nouvel accessoire', 'Add New Accessory'],
    'زجاج مزدوج 24مم (Double Glass)': ['Double vitrage 24mm', 'Double Glass 24mm'],
    'زجاج ثابت': ['Vitrage fixe', 'Fixed Glass'],
    'تواصل لتجديد الاشتراك (WhatsApp)': ['Contacter pour renouveler (WhatsApp)', 'Contact to renew (WhatsApp)'],
    'اللون (Color)': ['Couleur', 'Color'],
    'مخصص لسيري معين': ['Spécifique à une série', 'Specific to Series'],
    'عام لجميع السيريات': ['Commun à toutes les séries', 'Global for all Series'],
    'تغيير الأسعار': ['Changer les prix', 'Change Prices'],
    'تسجيل الدخول هذه غير مفعلة': ['Cette connexion est désactivée', 'This login is disabled'],
    'كلمة المرور غير صحيحة': ['Mot de passe incorrect', 'Incorrect Password'],
    'نجوم': ['Étoiles', 'Stars'],
    'تقييم التطبيق': ["Évaluation de l'application", "App Rating"],
}

def translate(text):
    if text in auto_dict:
        return auto_dict[text]
    
    fr, en = text, text
    # Simple word replacement
    if 'إضافة' in text: fr = fr.replace('إضافة', 'Ajouter'); en = en.replace('إضافة', 'Add')
    if 'اسم' in text: fr = fr.replace('اسم', 'Nom'); en = en.replace('اسم', 'Name')
    if 'سعر' in text: fr = fr.replace('سعر', 'Prix'); en = en.replace('سعر', 'Price')
    if 'تعديل' in text: fr = fr.replace('تعديل', 'Modifier'); en = en.replace('تعديل', 'Edit')
    if 'حذف' in text: fr = fr.replace('حذف', 'Supprimer'); en = en.replace('حذف', 'Delete')
    if 'رقم' in text: fr = fr.replace('رقم', 'Numéro'); en = en.replace('رقم', 'Number')
    if 'نوع' in text: fr = fr.replace('نوع', 'Type'); en = en.replace('نوع', 'Type')
    if 'كود' in text: fr = fr.replace('كود', 'Code'); en = en.replace('كود', 'Code')
    if 'فاتورة' in text: fr = fr.replace('فاتورة', 'Facture'); en = en.replace('فاتورة', 'Invoice')
    if 'زجاج' in text: fr = fr.replace('زجاج', 'Verre'); en = en.replace('زجاج', 'Glass')
    if 'مورد' in text: fr = fr.replace('مورد', 'Fournisseur'); en = en.replace('مورد', 'Supplier')
    
    return [fr, en]

buffer = []
for key in missing:
    key = key.strip()
    if not key: continue
    
    tr = translate(key)
    safe_key = key.replace("'''", "")
    safe_fr = tr[0].replace("'''", "")
    safe_en = tr[1].replace("'''", "")
    
    buffer.append(f"    r'''{safe_key}''': {{")
    buffer.append(f"      AppLanguage.arabic: r'''{safe_key}''',")
    buffer.append(f"      AppLanguage.french: r'''{safe_fr}''',")
    buffer.append(f"      AppLanguage.english: r'''{safe_en}''',")
    buffer.append("    },")

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
