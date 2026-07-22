import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

content = open('lib/settings/locales/general_keys.dart', encoding='utf-8').read()

# Let's extract keys matching 'something': {
keys = re.findall(r"^\s*'([^']+)':\s*\{", content, re.MULTILINE)
seen = set()
duplicates = []
for k in keys:
    if k in seen:
        duplicates.append(k)
    seen.add(k)

print("Total keys:", len(keys))
print("Duplicate keys found:")
for d in duplicates:
    print("-", d)
