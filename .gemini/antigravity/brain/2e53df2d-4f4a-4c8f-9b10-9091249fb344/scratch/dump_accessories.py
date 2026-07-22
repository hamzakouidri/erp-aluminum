import sqlite3

db_path = r'C:\Users\hp\Desktop\Noraleur\erp-aluminum-main\.dart_tool\sqflite_common_ffi\databases\test.db'

try:
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    
    # Let's see some accessories
    cursor.execute("SELECT id, name, type, price, material_type, scope, series_id, series_ids FROM Accessories LIMIT 30")
    rows = cursor.fetchall()
    
    print("--- ACCESSORIES IN DB ---")
    for r in rows:
        print(r)
        
    conn.close()
except Exception as e:
    print(f"Error: {e}")
