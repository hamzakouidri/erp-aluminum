import re

with open("lib/Commande/Systeme/cost_summary_screen.dart", "r", encoding="utf-8") as f:
    content = f.read()

# Replace dbInstance.query with dbInstance!.query and fix comma
bad_block = """    final dbInstance = await db.db;
    final sList = await dbInstance!.query('Series');
    final gList = await dbInstance.query('Glass');
    final shList = await dbInstance.query('Shutters');
    final jList = await dbInstance.query('Joints');
    final aList = await dbInstance.query('Accessories');
    final cList = await dbInstance.query('Colors');"""

good_block = """    final dbInstance = await db.db;
    final sList = await dbInstance!.query('Series');
    final gList = await dbInstance.query('Glass');
    final shList = await dbInstance.query('Shutters');
    final jList = await dbInstance.query('Joints');
    final aList = await dbInstance.query('Accessories');
    final cList = await dbInstance.query('Colors');"""

# Wait, the previous script hasn't run yet. Let's just do a clean replacement on the original text, but account for it if it DID run.
content = content.replace("await dbInstance.query", "await dbInstance!.query")
content = content.replace("await dbInstance!.query('Glass'),", "await dbInstance!.query('Glass');")

with open("lib/Commande/Systeme/cost_summary_screen.dart", "w", encoding="utf-8") as f:
    f.write(content)
