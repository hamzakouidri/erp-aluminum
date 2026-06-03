import re

with open("lib/Commande/Systeme/cost_summary_screen.dart", "r", encoding="utf-8") as f:
    content = f.read()

bad_block = """    final dbInstance = await db.db;
    final sList = await dbInstance!.query('Series');
    final gList = await dbInstance.query('Glass');
    final shList = await dbInstance.query('Shutters');
    final jList = await dbInstance.query('Joints');
    final aList = await dbInstance.query('Accessories');
    final cList = await dbInstance.query('Colors');"""

good_block = """    final dbInstance = (await db.db)!;
    final sList = await dbInstance.query('Series');
    final gList = await dbInstance.query('Glass');
    final shList = await dbInstance.query('Shutters');
    final jList = await dbInstance.query('Joints');
    final aList = await dbInstance.query('Accessories');
    final cList = await dbInstance.query('Colors');"""

content = content.replace(bad_block, good_block)

with open("lib/Commande/Systeme/cost_summary_screen.dart", "w", encoding="utf-8") as f:
    f.write(content)
