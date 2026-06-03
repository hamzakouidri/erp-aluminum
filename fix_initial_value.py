import os

def replace_value_with_initial_value(filepath, lines_to_fix):
    if not os.path.exists(filepath): return
    with open(filepath, 'r', encoding='utf-8') as f:
        lines = f.readlines()
        
    # The line numbers from flutter analyze are 1-indexed. We decrement by 1.
    for line_num in lines_to_fix:
        idx = line_num - 1
        if idx < len(lines) and 'value:' in lines[idx]:
            lines[idx] = lines[idx].replace('value:', 'initialValue:')
            
    with open(filepath, 'w', encoding='utf-8') as f:
        f.writelines(lines)

replace_value_with_initial_value('lib/Screen/ai_scanner_screen.dart', [918, 957])
replace_value_with_initial_value('lib/Screen/price_management_screen.dart', [289])
replace_value_with_initial_value('lib/items_produits/colors.dart', [75, 214])
