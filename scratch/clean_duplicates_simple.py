import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
lines = open(path, encoding='utf-8').read().splitlines()

new_lines = []
in_block = False
current_key = None
current_block_lines = []

seen_keys = set()
duplicates_removed = []

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
            if current_key in seen_keys:
                duplicates_removed.append(current_key)
            else:
                seen_keys.add(current_key)
                new_lines.extend(current_block_lines)
            current_block_lines = []
            current_key = None
        i += 1
    else:
        new_lines.append(line)
        i += 1

print("Duplicates removed:", duplicates_removed)
print("Unique keys count:", len(seen_keys))

open(path, 'w', encoding='utf-8').write("\n".join(new_lines) + "\n")
print("Successfully cleaned duplicates from general_keys.dart!")
