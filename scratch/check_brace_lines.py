import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
lines = open(path, encoding='utf-8').readlines()

brace_count = 0
for idx, line in enumerate(lines):
    old_count = brace_count
    brace_count += line.count('{') - line.count('}')
    if brace_count > 2:
        print(f"Line {idx+1}: count={brace_count} (was {old_count}): {line.strip()}")
        break
