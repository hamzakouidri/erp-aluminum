import sys

sys.stdout.reconfigure(encoding='utf-8')

path = 'lib/settings/locales/general_keys.dart'
content = open(path, encoding='utf-8').read()

# Let's remove string literals: '...' and "..."
# Since some strings span multiple lines, let's be careful. But in this file all strings are single-line.
# Let's replace anything between single quotes with empty string (excluding escaped quotes).
# A regex for single quoted strings: '([^'\\]|\\.)*'
no_strings = re_content = content
no_strings = re_content = re_content = re_content = re_content
import re
no_strings = re.sub(r"'([^'\\]|\\.)*'", "''", content)
no_strings = re.sub(r'"([^"\\]|\\.)*"', '""', no_strings)

print("Opening braces in code (no strings):", no_strings.count('{'))
print("Closing braces in code (no strings):", no_strings.count('}'))

# Now let's trace braces in no_strings!
brace_count = 0
lines = no_strings.splitlines()
for idx, line in enumerate(lines):
    old_count = brace_count
    brace_count += line.count('{') - line.count('}')
    if brace_count > 2 or brace_count < 0:
        print(f"Line {idx+1}: count={brace_count} (was {old_count}): {line.strip()}")
        if brace_count < 0:
            brace_count = 0
