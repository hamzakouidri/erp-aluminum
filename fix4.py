import sys

with open('lib/sql_database.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Update Commandes table
old_commandes = '''    CREATE TABLE Commandes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER NOT NULL,
      status TEXT,
      description TEXT,
      remise REAL DEFAULT 0.0,
      tva REAL DEFAULT 0.0,
      total REAL NOT NULL,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (client_id) REFERENCES Client(id) ON DELETE CASCADE
    )'''

new_commandes = '''    CREATE TABLE Commandes (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      client_id INTEGER NOT NULL,
      status TEXT,
      description TEXT,
      remise REAL DEFAULT 0.0,
      tva REAL DEFAULT 0.0,
      total REAL NOT NULL,
      advance_payment REAL DEFAULT 0.0,
      payment_status TEXT DEFAULT 'Unpaid',
      created_at TEXT DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT DEFAULT CURRENT_TIMESTAMP,
      FOREIGN KEY (client_id) REFERENCES Client(id) ON DELETE CASCADE
    )'''

content = content.replace(old_commandes, new_commandes)

# Add Treasury and WorkerTransactions tables
tables_insert_idx = content.find("    await db.execute('''\n        CREATE TABLE Profile (")
if tables_insert_idx != -1:
    new_tables = '''    await db.execute("""
    CREATE TABLE Treasury (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      transaction_type TEXT NOT NULL,
      amount REAL NOT NULL,
      description TEXT,
      reference_id INTEGER,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """);

    await db.execute("""
    CREATE TABLE WorkerTransactions (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      worker_uid TEXT NOT NULL,
      amount REAL NOT NULL,
      transaction_type TEXT NOT NULL,
      note TEXT,
      created_at TEXT DEFAULT CURRENT_TIMESTAMP
    )
    """);

'''
    new_tables = new_tables.replace('"""', "'''")
    content = content[:tables_insert_idx] + new_tables + content[tables_insert_idx:]

with open('lib/sql_database.dart', 'w', encoding='utf-8') as f:
    f.write(content)
