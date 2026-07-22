import re
import sys
import os

sys.stdout.reconfigure(encoding='utf-8')

glass_keys = [
    'شفاف', 'ستوبسول', 'صابلي', 'دلتا', 'تيسي', 'نيفادا', 'مطبخ', 'مورد', 'بانو', 'ارزين', 'بليكسي', 'بانو ديكور', 'بارداش', 'موسى', 'حراري', 'زجاج مسلح',
    'أزرق', 'بني', 'أخضر', 'رمادي', 'رمادي بلجيكي', 'ازرق بلجيكي',
    'ابيض', 'رمادي فاتح', 'خشبي داكن', 'رمادي داكن', 'اسود', 'باج', 'خشبي فاتح', 'عاتم', 'رخامي',
    'يسار', 'يمين', 'أعلى', 'أسفل'
]

locales_dir = 'lib/settings/locales'
content = ""
for f in os.listdir(locales_dir):
    content += open(os.path.join(locales_dir, f), encoding='utf-8').read()

for key in glass_keys:
    pattern = rf"'{key}':\s*\{{[^}}]*\}}"
    match = re.search(pattern, content)
    if match:
        print(f"Key found: {key}")
        # print the exact block
        print(match.group(0))
    else:
        pattern_double = rf'"{key}":\s*\{{[^}}]*\}}'
        match_double = re.search(pattern_double, content)
        if match_double:
            print(f"Key found: {key}")
            print(match_double.group(0))
        else:
            print(f"Key NOT found: {key}")
