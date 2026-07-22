import re

path_drawer = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Screen\drawer.dart'
path_accessoires = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\items_produits\accessoires.dart'
path_keys = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\settings\locales\general_keys.dart'

# ────────────────────────────────────────────────────
# 1. Update drawer.dart
# ────────────────────────────────────────────────────
with open(path_drawer, 'r', encoding='utf-8') as f:
    code_drawer = f.read()

OLD_DRAWER_COMMANDES = """          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.list),
              title: Text('commandes'),"""

NEW_DRAWER_COMMANDES = """          if (settings.canViewOrders())
            ListTile(
              leading: const Icon(Icons.list),
              title: Text(Localization.translate('commandes', lang)),"""

assert OLD_DRAWER_COMMANDES in code_drawer, "commandes tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_COMMANDES, NEW_DRAWER_COMMANDES, 1)

OLD_DRAWER_CLIENTS = """          if (settings.canViewClients())
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text('clients'),"""

NEW_DRAWER_CLIENTS = """          if (settings.canViewClients())
            ListTile(
              leading: const Icon(Icons.groups),
              title: Text(Localization.translate('clients', lang)),"""

assert OLD_DRAWER_CLIENTS in code_drawer, "clients tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_CLIENTS, NEW_DRAWER_CLIENTS, 1)

OLD_DRAWER_ACHAT = """          if (settings.canRegisterPurchases())
            ListTile(
              leading: const Icon(Icons.shopping_bag_rounded),
              title: Text('achat'),"""

NEW_DRAWER_ACHAT = """          if (settings.canRegisterPurchases())
            ListTile(
              leading: const Icon(Icons.shopping_bag_rounded),
              title: Text(Localization.translate('achat', lang)),"""

assert OLD_DRAWER_ACHAT in code_drawer, "achat tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_ACHAT, NEW_DRAWER_ACHAT, 1)

OLD_DRAWER_PRODUITS = """          if (settings.isManager)
            ListTile(
              leading: const Icon(Icons.production_quantity_limits),
              title: Text('produits'),"""

NEW_DRAWER_PRODUITS = """          if (settings.isManager)
            ListTile(
              leading: const Icon(Icons.production_quantity_limits),
              title: Text(Localization.translate('produits', lang)),"""

assert OLD_DRAWER_PRODUITS in code_drawer, "produits tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_PRODUITS, NEW_DRAWER_PRODUITS, 1)

OLD_DRAWER_CAISSE = """          if (settings.canAccessTreasury())
            ListTile(
              leading: const Icon(Icons.money),
              title: Text('caisse'),"""

NEW_DRAWER_CAISSE = """          if (settings.canAccessTreasury())
            ListTile(
              leading: const Icon(Icons.money),
              title: Text(Localization.translate('caisse', lang)),"""

assert OLD_DRAWER_CAISSE in code_drawer, "caisse tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_CAISSE, NEW_DRAWER_CAISSE, 1)

OLD_DRAWER_MANAGE_PRICES = """          if (settings.canChangePrices())
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: Text('Manage Prices'),"""

NEW_DRAWER_MANAGE_PRICES = """          if (settings.canChangePrices())
            ListTile(
              leading: const Icon(Icons.monetization_on),
              title: Text(Localization.translate('Manage Prices', lang)),"""

assert OLD_DRAWER_MANAGE_PRICES in code_drawer, "Manage Prices tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_MANAGE_PRICES, NEW_DRAWER_MANAGE_PRICES, 1)

OLD_DRAWER_SETTINGS = """          if (settings.isManager)
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text('settings'),"""

NEW_DRAWER_SETTINGS = """          if (settings.isManager)
            ListTile(
              leading: const Icon(Icons.settings),
              title: Text(Localization.translate('settings', lang)),"""

assert OLD_DRAWER_SETTINGS in code_drawer, "settings tile not found in drawer"
code_drawer = code_drawer.replace(OLD_DRAWER_SETTINGS, NEW_DRAWER_SETTINGS, 1)

with open(path_drawer, 'w', encoding='utf-8') as f:
    f.write(code_drawer)
print("drawer.dart updated successfully.")

# ────────────────────────────────────────────────────
# 2. Update accessoires.dart
# ────────────────────────────────────────────────────
with open(path_accessoires, 'r', encoding='utf-8') as f:
    code_accessoires = f.read()

OLD_SEARCH_HINT = """                hintText: 'البحث بالاسم أو النوع...',"""

NEW_SEARCH_HINT = """                hintText: Localization.translate('البحث بالاسم أو النوع...', Provider.of<AppSettingsProvider>(context, listen: false).language),"""

assert OLD_SEARCH_HINT in code_accessoires, "Search hintText not found in accessoires.dart"
code_accessoires = code_accessoires.replace(OLD_SEARCH_HINT, NEW_SEARCH_HINT, 1)

with open(path_accessoires, 'w', encoding='utf-8') as f:
    f.write(code_accessoires)
print("accessoires.dart updated successfully.")

# ────────────────────────────────────────────────────
# 3. Update general_keys.dart
# ────────────────────────────────────────────────────
with open(path_keys, 'r', encoding='utf-8') as f:
    code_keys = f.read()

# Let's insert the new translation keys at the top of the map or near any known key
ANCHOR_KEY = """  'إدارة الكيت': {"""
NEW_KEYS = """  'commandes': {
    AppLanguage.arabic: 'الطلبيات',
    AppLanguage.french: 'Commandes',
    AppLanguage.english: 'Orders',
  },
  'clients': {
    AppLanguage.arabic: 'الزبائن',
    AppLanguage.french: 'Clients',
    AppLanguage.english: 'Customers',
  },
  'achat': {
    AppLanguage.arabic: 'المشتريات',
    AppLanguage.french: 'Achats',
    AppLanguage.english: 'Purchases',
  },
  'produits': {
    AppLanguage.arabic: 'المنتجات',
    AppLanguage.french: 'Produits',
    AppLanguage.english: 'Products',
  },
  'caisse': {
    AppLanguage.arabic: 'صندوق',
    AppLanguage.french: 'Caisse',
    AppLanguage.english: 'Cash Flow',
  },
  'Manage Prices': {
    AppLanguage.arabic: 'إدارة الأسعار',
    AppLanguage.french: 'Gérer les prix',
    AppLanguage.english: 'Manage Prices',
  },
  'settings': {
    AppLanguage.arabic: 'الإعدادات',
    AppLanguage.french: 'Paramètres',
    AppLanguage.english: 'Settings',
  },
  'البحث بالاسم أو النوع...': {
    AppLanguage.arabic: 'البحث بالاسم أو النوع...',
    AppLanguage.french: 'Recherche par nom ou type...',
    AppLanguage.english: 'Search by name or type...',
  },
  'البحث بالاسم...': {
    AppLanguage.arabic: 'البحث بالاسم...',
    AppLanguage.french: 'Recherche par nom...',
    AppLanguage.english: 'Search by name...',
  },
  'البحث بالنوع...': {
    AppLanguage.arabic: 'البحث بالنوع...',
    AppLanguage.french: 'Recherche par type...',
    AppLanguage.english: 'Search by type...',
  },
  'إدارة الكيت': {"""

assert ANCHOR_KEY in code_keys, "Anchor key not found in general_keys.dart"
code_keys = code_keys.replace(ANCHOR_KEY, NEW_KEYS, 1)

with open(path_keys, 'w', encoding='utf-8') as f:
    f.write(code_keys)
print("general_keys.dart updated successfully.")
