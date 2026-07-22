import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

screens = [
    'lib/Screen/inventory_screen.dart',
    'lib/Screen/inventory_adjustment_screen.dart',
    'lib/Screen/inventory_item_history_screen.dart',
    'lib/Screen/suppliers_screen.dart',
    'lib/Screen/supplier_details_screen.dart',
    'lib/Screen/achat_screen.dart',
    'lib/Screen/achat_details_screen.dart',
    'lib/Screen/price_management_screen.dart'
]

# Find all arabic strings in the code
# An arabic string contains at least one arabic character: [\u0600-\u06FF]
for screen in screens:
    if not os.path.exists(screen):
        print(f"File not found: {screen}")
        continue
    print(f"\n=== Screen: {screen} ===")
    content = open(screen, encoding='utf-8').read()
    lines = content.split('\n')
    for idx, line in enumerate(lines):
        # search for arabic characters inside quotes
        matches = re.findall(r"['\"]([^'\"]*[\u0600-\u06FF]+[^'\"]*)['\"]", line)
        if matches:
            # check if it is not a comment and doesn't already use translate
            clean_line = line.strip()
            if not clean_line.startswith('//') and 'Localization.translate' not in clean_line and 't(' not in clean_line:
                print(f"  L{idx+1}: {clean_line} (Arabic text: {matches})")
