with open(r"c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\show_system_francais.dart", "r", encoding="utf-8") as f:
    lines = f.readlines()

stack = []
for idx, line in enumerate(lines):
    line_num = idx + 1
    for char_idx, char in enumerate(line):
        if char == '{':
            stack.append((line_num, line.strip()))
        elif char == '}':
            if not stack:
                print(f"Extra closing brace at line {line_num}: {line.strip()}")
            else:
                stack.pop()

if stack:
    print("Unmatched open braces remaining at EOF:")
    for item in stack[-10:]:
        print(f"Line {item[0]}: {item[1]}")
