import sys

content = """import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class AccessoriesScreen extends StatefulWidget {
  final SqlDatabase db;
  const AccessoriesScreen({super.key, required this.db});

  @override
  State<AccessoriesScreen> createState() => _AccessoriesScreenState();
}

class _AccessoriesScreenState extends State<AccessoriesScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _series = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readAccessories();
    final dbInstance = await widget.db.db;
    final series = await dbInstance!.query('Series');
    setState(() {
      _items = items;
      _series = series;
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    String materialType = 'Aluminium';
    String scope = 'Global';
    int? selectedSeriesId;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('إضافة أكسسوار جديد', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl, 
                  decoration: InputDecoration(labelText: Localization.translate('اسم الأكسسوار', Provider.of<AppSettingsProvider>(context).language))
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: materialType,
                  items: ['Aluminium', 'PVC'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      materialType = newValue!;
                      if (materialType == 'PVC') {
                        scope = 'Global';
                      }
                    });
                  },
                  decoration: InputDecoration(labelText: Localization.translate('Material Type', Provider.of<AppSettingsProvider>(context).language)),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: scope,
                  items: ['Global', 'Unique'].map((String value) {
                    String translatedValue = value == 'Global' 
                        ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language) 
                        : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language);
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: materialType == 'PVC' ? null : (newValue) {
                    setStateDialog(() {
                      scope = newValue!;
                    });
                  },
                  decoration: InputDecoration(labelText: Localization.translate('Scope', Provider.of<AppSettingsProvider>(context).language)),
                ),
                if (scope == 'Unique') ...[
                  SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: selectedSeriesId,
                    items: _series.map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['name'].toString()),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setStateDialog(() {
                        selectedSeriesId = newValue;
                      });
                    },
                    decoration: InputDecoration(labelText: Localization.translate('Series', Provider.of<AppSettingsProvider>(context).language)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final dbInstance = await widget.db.db;
                  await dbInstance!.insert('Accessories', {
                    'name': nameCtrl.text,
                    'material_type': materialType,
                    'scope': scope,
                    'series_id': scope == 'Unique' ? selectedSeriesId : null,
                    'type': materialType, // generic
                    'price': 0.0 // Prices are handled in PriceManagementScreen
                  });
                  _loadItems();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    final nameCtrl = TextEditingController(text: item['name']);
    String materialType = item['material_type']?.toString() ?? 'Aluminium';
    String scope = item['scope']?.toString() ?? 'Global';
    int? selectedSeriesId = item['series_id'] as int?;

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('تعديل', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl, 
                  decoration: InputDecoration(labelText: Localization.translate('اسم الأكسسوار', Provider.of<AppSettingsProvider>(context).language))
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: materialType,
                  items: ['Aluminium', 'PVC'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      materialType = newValue!;
                      if (materialType == 'PVC') {
                        scope = 'Global';
                      }
                    });
                  },
                  decoration: InputDecoration(labelText: Localization.translate('Material Type', Provider.of<AppSettingsProvider>(context).language)),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  value: scope,
                  items: ['Global', 'Unique'].map((String value) {
                    String translatedValue = value == 'Global' 
                        ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language) 
                        : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language);
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: materialType == 'PVC' ? null : (newValue) {
                    setStateDialog(() {
                      scope = newValue!;
                    });
                  },
                  decoration: InputDecoration(labelText: Localization.translate('Scope', Provider.of<AppSettingsProvider>(context).language)),
                ),
                if (scope == 'Unique') ...[
                  SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    value: selectedSeriesId,
                    items: _series.map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text(s['name'].toString()),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setStateDialog(() {
                        selectedSeriesId = newValue;
                      });
                    },
                    decoration: InputDecoration(labelText: Localization.translate('Series', Provider.of<AppSettingsProvider>(context).language)),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  final dbInstance = await widget.db.db;
                  await dbInstance!.update('Accessories', {
                    'name': nameCtrl.text,
                    'material_type': materialType,
                    'scope': scope,
                    'series_id': scope == 'Unique' ? selectedSeriesId : null,
                    'type': materialType,
                  }, where: 'id = ?', whereArgs: [item['id']]);
                  _loadItems();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = Provider.of<AppSettingsProvider>(context).isManager;
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('الإكسسوارات', Provider.of<AppSettingsProvider>(context).language)),
      ),
      body: _items.isEmpty
          ? Center(child: Text(Localization.translate('لا توجد بيانات', Provider.of<AppSettingsProvider>(context).language)))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                String subtitle = "${item['material_type']} - ";
                subtitle += item['scope'] == 'Global' 
                    ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language)
                    : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language);

                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      item['name'].toString(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                    ),
                    subtitle: Text(subtitle),
                    trailing: !isUserAdmin ? null : Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                          onPressed: () => _showEditDialog(item),
                        ),
                        IconButton(
                          icon: Icon(Icons.delete, color: Colors.red, size: 20),
                          onPressed: () async {
                            final dbInstance = await widget.db.db;
                            await dbInstance!.delete('Accessories', where: 'id = ?', whereArgs: [item['id']]);
                            _loadItems();
                          },
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: !isUserAdmin ? null : FloatingActionButton(
        onPressed: _showAddDialog,
        child: Icon(Icons.add),
      ),
    );
  }
}
"""

with open('lib/items_produits/accessoires.dart', 'w', encoding='utf-8') as f:
    f.write(content)
