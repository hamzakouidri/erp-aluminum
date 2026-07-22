with open(r"c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\show_system_francais.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

stack = []
for idx, line in enumerate(lines):
    line_num = idx + 1
    # Check for method/class definitions to print context
    if "class " in line or "void " in line or "Widget " in line or "onPressed:" in line or "showModalBottomSheet" in line:
        context = line.strip()
    else:
        context = ""
    
    for char in line:
        if char == '{':
            stack.append((line_num, context or line.strip()))
        elif char == '}':
            if stack:
                stack.pop()

print("Current unmatched braces stack at the end:")
for s in stack:
    print(f"Line {s[0]}: {s[1]}")
