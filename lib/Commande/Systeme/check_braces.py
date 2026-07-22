with open(r"c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\show_system_francais.dart", "r", encoding="utf-8") as f:
    content = f.read()

open_braces = content.count('{')
close_braces = content.count('}')
print(f"Open: {open_braces}, Close: {close_braces}, Diff: {open_braces - close_braces}")
