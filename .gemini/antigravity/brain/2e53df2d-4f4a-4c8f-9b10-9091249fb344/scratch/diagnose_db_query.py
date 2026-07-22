path_consumption = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\material_consumption_screen.dart'

with open(path_consumption, 'r', encoding='utf-8') as f:
    lines = f.readlines()

print(f"Total lines: {len(lines)}")

# Let's find all lines containing "db.query" and print them
for i, line in enumerate(lines):
    if 'db.query(' in line:
        print(f"Line {i+1}: {line.strip()}")
