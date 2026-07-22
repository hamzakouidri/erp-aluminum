import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

import re
match = re.search(r'(const\s+Map<String,\s+Map<AppLanguage,\s+String>>\s+generalKeys\s*=\s*\{)', content)
if not match:
    print("Not matched")
    sys.exit(1)

map_content = content[match.end():]
print("Map content length:", len(map_content))

brace_count = 1
for idx, char in enumerate(map_content):
    if char == '{':
        brace_count += 1
    elif char == '}':
        brace_count -= 1
        if brace_count == 0:
            print(f"Found closing brace at index {idx}, character: {repr(map_content[idx:idx+10])}")
            break

print("Final brace count at end of loop:", brace_count)
