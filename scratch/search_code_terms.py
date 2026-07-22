import os
import sys

sys.stdout.reconfigure(encoding='utf-8')
terms = [
    'الكمية والتكلفة', 'وضع الرسم', 'وضع التحريك', 'القياس', 'إعدادات السعر', 
    'تفاصيل الحساب', 'قطعة', 'حبة', 'متر', 'سعر التكلفة الإجمالي', 
    'سعر القطعة', 'سعر البيع', 'العرض', 'الارتفاع', 'جدول السلع',
    'مراسلة الإدارة', 'المخزون', 'الموردين', 'المشتريات', 'البروفيلات', 
    'الأنظمة', 'الزجاج', 'ستوب صول', 'مركبات الستار', 'الإكسسوارات', 
    'ألوانات', 'الكيت'
]

lib_dir = 'lib'
results = {}

for root, dirs, files in os.walk(lib_dir):
    for f in files:
        if f.endswith('.dart'):
            path = os.path.join(root, f)
            try:
                content = open(path, encoding='utf-8').read()
            except Exception:
                continue
            for term in terms:
                if term in content:
                    # find all lines containing the term
                    lines = content.split('\n')
                    for idx, line in enumerate(lines):
                        if term in line:
                            results.setdefault(term, []).append((path, idx+1, line.strip()))

for term in terms:
    print(f"=== Term: {term} ===")
    if term in results:
        # print at most 10 occurrences
        for path, line_no, content in results[term][:15]:
            print(f"  {path}:{line_no} -> {content}")
    else:
        print("  NOT FOUND IN CODE")
