import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace(
    "'ShutterComponents', 'SeriesColorPrices', 'ProfileColors'",
    "'ShutterComponents', 'SeriesColorPrices', 'ProfileColors', 'Employees'"
)

content = content.replace(
    "'ProfileColors', 'SeriesColorPrices', 'ShutterComponents', 'Glass', 'Joints',",
    "'Employees', 'ProfileColors', 'SeriesColorPrices', 'ShutterComponents', 'Glass', 'Joints',"
)

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
