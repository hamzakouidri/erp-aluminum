import re
import sys
import os

sys.stdout.reconfigure(encoding='utf-8')
locales_dir = 'lib/settings/locales'
files = os.listdir(locales_dir)

terms = [
    'الكمية والتكلفة', 'وضع الرسم', 'وضع التحريك', 'القياس', 'إعدادات السعر', 
    'تفاصيل الحساب', 'قطعة', 'حبة', 'متر', 'سعر التكلفة الإجمالي', 
    'سعر القطعة', 'سعر البيع', 'العرض', 'الارتفاع', 'جدول السلع',
    'مراسلة الإدارة', 'المخزون', 'الموردين', 'المشتريات', 'البروفيلات', 
    'الأنظمة', 'الزجاج', 'ستوب صول', 'مركبات الستار', 'الإكسسوارات', 
    'ألوانات', 'الكيت'
]

found_terms = {}

for f in files:
    path = os.path.join(locales_dir, f)
    content = open(path, encoding='utf-8').read()
    for term in terms:
        # Find exact matches like 'term': { ... }
        # Note: the braces can span multiple lines
        pattern = rf"'{term}':\s*\{{[^}}]*\}}"
        matches = re.finditer(pattern, content)
        for m in matches:
            found_terms.setdefault(term, []).append((f, m.group(0)))
            
        pattern_double = rf'"{term}":\s*\{{[^}}]*\}}'
        matches_double = re.finditer(pattern_double, content)
        for m in matches_double:
            found_terms.setdefault(term, []).append((f, m.group(0)))

for term in terms:
    if term in found_terms:
        print(f"=== Term: {term} ===")
        for file_name, block in found_terms[term]:
            print(f"File: {file_name}\nBlock:\n{block}\n")
    else:
        print(f"=== Term: {term} === NOT FOUND ANYWHERE\n")
