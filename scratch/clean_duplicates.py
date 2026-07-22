import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

# We can find generalKeys = {
match = re.search(r'(const\s+Map<String,\s+Map<AppLanguage,\s+String>>\s+generalKeys\s*=\s*\{)', content)
if not match:
    print("generalKeys map declaration not found!")
    sys.exit(1)

start_idx = match.end()
# The rest of the content up to the closing };
map_content = content[start_idx:]

# Let's find the closing };
# We can track braces to find the end of generalKeys map
brace_count = 1
end_idx = -1
for idx, char in enumerate(map_content):
    if char == '{':
        brace_count += 1
    elif char == '}':
        brace_count -= 1
        if brace_count == 0:
            end_idx = idx
            break

if end_idx == -1:
    print("Could not find the closing brace of generalKeys!")
    sys.exit(1)

map_entries_str = map_content[:end_idx]
footer = map_content[end_idx:]

# Now, let's parse the entries. Each entry starts with:
# 'key': { ... } or "key": { ... }
entries = []
seen_keys = set()
duplicates_removed = []

pos = 0
while pos < len(map_entries_str):
    m = re.search(r"^\s*'([^']+)':\s*\{", map_entries_str[pos:], re.MULTILINE)
    if not m:
        break
    key = m.group(1)
    key_start = pos + m.start()
    
    # Let's find the closing } of this entry
    brace_c = 1
    entry_end = -1
    for i in range(key_start + m.end() - m.start(), len(map_entries_str)):
        if map_entries_str[i] == '{':
            brace_c += 1
        elif map_entries_str[i] == '}':
            brace_c -= 1
            if brace_c == 0:
                entry_end = i
                break
    
    if entry_end == -1:
        print(f"Failed to find closing brace for key: {key}")
        sys.exit(1)
    
    # Extract the full entry string (including trailing comma if present)
    next_pos = entry_end + 1
    # Check if there is a trailing comma or whitespace
    while next_pos < len(map_entries_str) and map_entries_str[next_pos] in [',', '\r', '\n', ' ']:
        next_pos += 1
        
    entry_full_str = map_entries_str[key_start:next_pos]
    
    if key in seen_keys:
        duplicates_removed.append(key)
    else:
        seen_keys.add(key)
        entries.append(entry_full_str)
        
    pos = next_pos

print("Removed duplicates:", duplicates_removed)
print("Unique keys count:", len(seen_keys))

# Reconstruct file
new_content = content[:start_idx] + "\n" + "".join(entries) + footer
open(path, 'w', encoding='utf-8').write(new_content)
print("Done removing duplicates successfully!")
