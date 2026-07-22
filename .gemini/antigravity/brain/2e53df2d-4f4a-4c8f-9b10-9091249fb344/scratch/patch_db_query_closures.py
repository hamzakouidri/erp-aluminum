path_consumption = r'c:\Users\hp\Desktop\Noraleur\erp-aluminum-main\lib\Commande\Systeme\material_consumption_screen.dart'

with open(path_consumption, 'r', encoding='utf-8') as f:
    code = f.read()

# 1. Add final Database dbInstance = db; (We already added it in CP, but let's make sure it's correct)
# Wait, let's look at what is in the code now around line 260.
# The code currently has:
#     final db = await SqlDatabase().db; // اتصال قاعدة البيانات لباقي عمليات الجلب
#     if (db == null) return; // بدون اتصال ما فيه داعي نكمل
#     final Database dbInstance = db;
# Yes, we already added it in the previous turn. So we just need to replace the db.query calls inside _fetchDefaults!

# 2. Locate the _fetchDefaults body boundaries
start_idx = code.find("Future<void> _fetchDefaults() async {")
end_idx = code.find("void _onModelChanged() {", start_idx)

if start_idx != -1 and end_idx != -1:
    body = code[start_idx:end_idx]
    # Replace db.query( with dbInstance.query( inside the body of _fetchDefaults
    new_body = body.replace("db.query(", "dbInstance.query(")
    code = code[:start_idx] + new_body + code[end_idx:]
    print("Replaced db.query with dbInstance.query inside _fetchDefaults successfully.")
else:
    print("Could not find _fetchDefaults boundaries.")

with open(path_consumption, 'w', encoding='utf-8') as f:
    f.write(code)
print("material_consumption_screen.dart updated successfully.")
