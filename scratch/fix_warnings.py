import re

# Fix drawer.dart
with open('lib/Screen/drawer.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace('SqlDatabase db = SqlDatabase();', 'final SqlDatabase db = SqlDatabase();')
content = content.replace('String? joinCode;\n', '')
content = content.replace('joinCode = data[\'joinCode\'];\n', '')

with open('lib/Screen/drawer.dart', 'w', encoding='utf-8') as f:
    f.write(content)

# Fix consumption_report_screen.dart
with open('lib/Screen/consumption_report_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'\.withOpacity\((.*?)\)', r'.withValues(alpha: \1)', content)
# comment out unused method declaration
content = content.replace('Future<void> _generatePurchasePdf(ConsumptionReport report) async {', '// Future<void> _generatePurchasePdf(ConsumptionReport report) async {')

with open('lib/Screen/consumption_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

# Fix global_consumption_report_screen.dart
with open('lib/Screen/global_consumption_report_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = re.sub(r'\.withOpacity\((.*?)\)', r'.withValues(alpha: \1)', content)

with open('lib/Screen/global_consumption_report_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)

print("Done fixing warnings")
