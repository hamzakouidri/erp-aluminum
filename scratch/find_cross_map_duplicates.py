import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

files = {
    'mainMenuKeys': 'lib/settings/locales/main_menu_keys.dart',
    'drawerKeys': 'lib/settings/locales/drawer_keys.dart',
    'productKeys': 'lib/settings/locales/product_keys.dart',
    'orderKeys': 'lib/settings/locales/order_keys.dart',
    'generalKeys': 'lib/settings/locales/general_keys.dart'
}

all_keys = {}
for name, path in files.items():
    content = open(path, encoding='utf-8').read()
    # Find keys matching 'key': {
    keys = re.findall(r"^\s*'([^']+)':\s*\{", content, re.MULTILINE)
    all_keys[name] = set(keys)
    print(f"{name} has {len(keys)} keys")

# Find duplicates between pairs of maps
from collections import defaultdict
key_occurrences = defaultdict(list)
for name, keys in all_keys.items():
    for k in keys:
        key_occurrences[k].append(name)

duplicates = {k: v for k, v in key_occurrences.items() if len(v) > 1}

print("\nDuplicate keys across maps:")
for k, v in duplicates.items():
    print(f"Key '{k}' is in: {v}")
