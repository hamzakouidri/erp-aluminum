path_consumption = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\material_consumption_screen.dart'

with open(path_consumption, 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if 'db = await' in line or 'db = SqlDatabase()' in line:
        # Avoid printing Arabic characters directly to standard output
        clean_line = "".join([c if ord(c) < 128 else '?' for c in line.strip()])
        print(f"Line {i+1}: {clean_line}")
