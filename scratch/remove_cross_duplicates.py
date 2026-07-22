import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
lines = open(path, encoding='utf-8').read().splitlines()

keys_to_remove = {
    'ألوانات',
    'مركبات الستار',
    'الكيت',
    'اللون: ',
    'يرجى إدخال رقم الفاتورة',
    'تم حذف الفاتورة نهائياً',
    'البحث برقم الفاتورة أو اسم المورد...',
    'رقم الفاتورة *'
}

new_lines = []
in_block = False
current_key = None
current_block_lines = []

removed_count = 0

i = 0
while i < len(lines):
    line = lines[i]
    stripped = line.strip()
    # Check for start of block
    if not in_block and stripped.startswith("'") and (stripped.endswith("{") or stripped.endswith("{,")):
        parts = stripped.split("':")
        if len(parts) >= 2:
            current_key = parts[0].strip("'")
            in_block = True
            current_block_lines = [line]
            i += 1
            continue
            
    if in_block:
        current_block_lines.append(line)
        if stripped == '},' or stripped == '}':
            in_block = False
            if current_key in keys_to_remove:
                print(f"Removing duplicate cross key: {current_key}")
                removed_count += 1
            else:
                new_lines.extend(current_block_lines)
            current_block_lines = []
            current_key = None
        i += 1
    else:
        new_lines.append(line)
        i += 1

print(f"Total cross duplicates removed: {removed_count}")

open(path, 'w', encoding='utf-8').write("\n".join(new_lines) + "\n")
print("Done cleaning cross duplicates!")
