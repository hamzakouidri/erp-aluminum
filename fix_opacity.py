import os
import re

def fix_file(path):
    with open(path, 'r', encoding='utf-8') as f:
        content = f.read()

    # Replace withOpacity(x) with withValues(alpha: x)
    # The regex captures the number inside the parentheses
    new_content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
    
    # Replace value: with initialValue: for FormFields (this is a bit risky if it catches other things, but let's be careful)
    # We saw warnings about 'value' is deprecated... use initialValue instead.
    # We will specifically target the lines from the analyze output
    
    if content != new_content:
        with open(path, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Updated {path}")

for root, _, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            fix_file(os.path.join(root, file))
