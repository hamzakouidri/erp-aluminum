import sqlite3
import os

db_path = 'windows_devis_db.db'
if not os.path.exists(db_path):
    print("DB not found at", db_path)
    exit()

conn = sqlite3.connect(db_path)
cursor = conn.cursor()

cursor.execute("SELECT id, name, type FROM Profiles")
profiles = cursor.fetchall()
print("--- Profiles ---")
for p in profiles:
    print(f"Profile {p[0]}: {p[1]} ({p[2]})")
    cursor.execute("SELECT id, name, type FROM Series WHERE profile_id = ?", (p[0],))
    series = cursor.fetchall()
    for s in series:
        cursor.execute("SELECT COUNT(*) FROM Sections WHERE series_id = ?", (s[0],))
        count = cursor.fetchone()[0]
        print(f"  -> Series {s[0]}: {s[1]} ({s[2]}) - Sections count: {count}")

conn.close()
