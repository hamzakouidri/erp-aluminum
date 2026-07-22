import re
import sys

def escape_arabic(match):
    text = match.group(0)
    return ''.join(f'\\u{ord(c):04x}' for c in text)

def process_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()

    # Match any Arabic character block (0x0600 - 0x06FF)
    pattern = re.compile(r'[\u0600-\u06FF]+')
    
    new_content = pattern.sub(escape_arabic, content)
    
    with open(filepath, 'w', encoding='utf-8') as f:
        f.write(new_content)

for f in sys.argv[1:]:
    process_file(f)
