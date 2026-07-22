import os
import re
import sys

sys.stdout.reconfigure(encoding='utf-8')

for root, dirs, files in os.walk('lib'):
    for file in files:
        if file.endswith('.dart'):
            path = os.path.join(root, file)
            content = open(path, encoding='utf-8').read()
            if 'toMap' in content:
                # Find all occurrences of toMap
                matches = list(re.finditer(r'toMap\s*\(', content))
                if matches:
                    print(f"{file} has toMap at line(s):")
                    for m in matches:
                        line_no = content[:m.start()].count('\n') + 1
                        print(f"  Line {line_no}")
