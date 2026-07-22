import os
import re

def restore_unicode_escapes(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Find \uXXXX and convert to char
    def repl(match):
        hex_val = match.group(1)
        return chr(int(hex_val, 16))

    new_content = re.sub(r'\\u([0-9a-fA-F]{4})', repl, content)

    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Restored: {filepath}")

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            restore_unicode_escapes(os.path.join(root, file))
