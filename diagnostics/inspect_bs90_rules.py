import sqlite3
import sys
from pathlib import Path

connection = sqlite3.connect(Path(sys.argv[1]).resolve().as_uri() + '?mode=ro', uri=True)
connection.row_factory = sqlite3.Row
series = connection.execute('SELECT id,name,type FROM Series').fetchall()
for row in series:
    if 'bs90' not in row['name'].lower().replace(' ', ''):
        continue
    print(dict(row))
    print([dict(s) for s in connection.execute('SELECT id,code,name,type FROM Sections WHERE series_id = ?', (row['id'],))])
    rules = connection.execute('SELECT * FROM CatalogItemRules WHERE series_id = ?', (row['id'],)).fetchall()
    for rule in rules:
        if rule['role_key'] in ('clam','clamp','frame_clamp','sash_clamp','sliding_clamp','sliding_lock','assembly_screw','installation_screw','accessory_screw','handle','entrematique','joint_vitrage'):
            print(dict(rule))
            if rule['item_table'] == 'Accessories':
                item = connection.execute('SELECT * FROM Accessories WHERE id = ?', (rule['item_id'],)).fetchone()
                if item:
                    print({key: item[key] for key in ('id','name','material_type','series_id','series_ids','is_active') if key in item.keys()})
connection.close()
