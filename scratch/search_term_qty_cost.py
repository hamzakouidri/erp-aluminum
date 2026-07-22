import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
term = 'الكمية والتكلفة'
for root, dirs, files in os.walk('lib'):
    for f in files:
        if f.endswith('.dart'):
            path = os.path.join(root, f)
            try:
                content = open(path, encoding='utf-8').read()
            except Exception:
                continue
            if term in content:
                print(f"Found in {path}")
                for idx, line in enumerate(content.split('\n')):
                    if term in line:
                        print(f"  L{idx+1}: {line.strip()}")
