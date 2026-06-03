import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class GlassScreen extends StatefulWidget {
  final SqlDatabase db;

  const GlassScreen({super.key, required this.db});

  @override
  State<GlassScreen> createState() => _GlassScreenState();
}

class _GlassScreenState extends State<GlassScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readGlass();
    setState(() {
      _items = items;
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final thicknessCtrl = TextEditingController();
    final priceCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate(
            'إضافة زجاج جديد',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'اسم الزجاج',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: typeCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'نوع الزجاج:',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: thicknessCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'السماكة',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: priceCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'سعر المتر المربع',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              Localization.translate(
                'إلغاء',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await widget.db.insertGlass(
                  nameCtrl.text,
                  typeCtrl.text,
                  double.tryParse(thicknessCtrl.text) ?? 0.0,
                  double.tryParse(priceCtrl.text) ?? 0.0,
                );
                _loadItems();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(
              Localization.translate(
                'حفظ',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, bool isUserAdmin) {
    final nameCtrl = TextEditingController(text: item['name'].toString());
    final typeCtrl = TextEditingController(text: item['type'].toString());
    final thicknessCtrl = TextEditingController(
      text: item['thickness'].toString(),
    );
    final priceCtrl = TextEditingController(
      text: item['price_per_sqm'].toString(),
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          Localization.translate(
            'تعديل',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              enabled: isUserAdmin,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'اسم الزجاج',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: typeCtrl,
              enabled: isUserAdmin,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'نوع الزجاج:',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: thicknessCtrl,
              enabled: isUserAdmin,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'السماكة',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
            TextField(
              controller: priceCtrl,
              decoration: InputDecoration(
                labelText: Localization.translate(
                  'سعر المتر المربع',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              Localization.translate(
                'إلغاء',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(color: Colors.grey),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
            onPressed: () async {
              if (nameCtrl.text.isNotEmpty) {
                await widget.db.updateGlass(
                  item['id'],
                  nameCtrl.text,
                  typeCtrl.text,
                  double.tryParse(thicknessCtrl.text) ?? 0.0,
                  double.tryParse(priceCtrl.text) ?? 0.0,
                );
                _loadItems();
                if (context.mounted) {
                  Navigator.pop(context);
                }
              }
            },
            child: Text(
              Localization.translate(
                'حفظ تعديل',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;
    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'إدارة الزجاج',
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
      ),
      body: _items.isEmpty
          ? Center(
              child: Text(
                Localization.translate(
                  'لا توجد بيانات',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            )
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    title: Text(
                      item['name'].toString(),
                      style: TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(item.toString()),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                          onPressed: () => _showEditDialog(item, isUserAdmin),
                        ),
                        if (isUserAdmin)
                          IconButton(
                            icon: Icon(Icons.delete, color: Colors.red, size: 20),
                            onPressed: () async {
                              await widget.db.deleteGlass(item['id']);
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
