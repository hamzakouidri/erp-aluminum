import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class ShuttersScreen extends StatefulWidget {
  final SqlDatabase db;

  const ShuttersScreen({super.key, required this.db});

  @override
  State<ShuttersScreen> createState() => _ShuttersScreenState();
}

class _ShuttersScreenState extends State<ShuttersScreen> {
  List<Map<String, dynamic>> _items = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readShutterComponents();
    setState(() {
      _items = items;
    });
  }

  void _showAddDialog() {
    final nameCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String selectedType = 'box';

    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final types = {
      'box': Localization.translate('صندوق', lang),
      'blade': Localization.translate('شفرة/شريحة', lang),
      'track': Localization.translate('سكة/مسار', lang),
      'motor': Localization.translate('محرك', lang),
      'kit': Localization.translate('كيت (Kit)', lang),
      'laxe': Localization.translate('أنبوب المحرك (L\'axe)', lang),
      'final_blade': Localization.translate('الشفرة النهائية', lang),
    };

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('إضافة مركب للستار', lang),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate('اسم المركب (مثال: محرك سومفي)', lang),
                    border: OutlineInputBorder(),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  decoration: InputDecoration(
                    labelText: Localization.translate('النوع', lang),
                    border: OutlineInputBorder(),
                  ),
                  items: types.entries.map((e) => DropdownMenuItem(
                    value: e.key,
                    child: Text(e.value),
                  )).toList(),
                  onChanged: (val) {
                    setStateDialog(() {
                      selectedType = val!;
                    });
                  },
                ),
                SizedBox(height: 10),
                TextField(
                  controller: priceCtrl,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: Localization.translate('السعر (بالقطعة)', lang),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton(
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty && priceCtrl.text.isNotEmpty) {
                  await widget.db.insertShutterComponent(
                    nameCtrl.text,
                    selectedType,
                    double.tryParse(priceCtrl.text) ?? 0.0,
                    'piece',
                  );
                  if (context.mounted) Navigator.pop(context);
                  _loadItems();
                }
              },
              child: Text(Localization.translate('إضافة', lang)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin; // from app_settings
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return Scaffold(
      appBar: AppBar(title: Text(Localization.translate('مركبات الستائر', lang))),
      body: ListView.builder(
        itemCount: _items.length,
        itemBuilder: (context, index) {
          final item = _items[index];
          String typeAr = '';
          switch (item['component_type']) {
            case 'box': typeAr = Localization.translate('صندوق', lang); break;
            case 'blade': typeAr = Localization.translate('شفرات', lang); break;
            case 'track': typeAr = Localization.translate('سكك', lang); break;
            case 'motor': typeAr = Localization.translate('محرك', lang); break;
            case 'kit': typeAr = Localization.translate('كيت (Kit)', lang); break;
            case 'laxe': typeAr = Localization.translate('أنبوب المحرك (L\'axe)', lang); break;
            case 'final_blade': typeAr = Localization.translate('الشفرة النهائية', lang); break;
            default: typeAr = item['component_type'];
          }

          return Card(
            margin: EdgeInsets.all(8),
            child: ListTile(
              title: Text(item['name'], style: TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text('${Localization.translate("النوع:", lang)} $typeAr - ${Localization.translate("السعر:", lang)} ${item['price']} ${Localization.translate("د.ج (بالقطعة)", lang)}'),
              trailing: isUserAdmin ? IconButton(
                icon: Icon(Icons.delete, color: Colors.red),
                onPressed: () async {
                  await widget.db.deleteShutterComponent(item['id']);
                  _loadItems();
                },
              ) : null,
            ),
          );
        },
      ),
      floatingActionButton: isUserAdmin ? FloatingActionButton(
        onPressed: _showAddDialog,
        child: Icon(Icons.add),
      ) : null,
    );
  }
}
