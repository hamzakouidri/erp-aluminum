import 'package:flutter/material.dart';
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
    final series = await dbInstance!.rawQuery('''
      SELECT s.*, p.name as profile_name 
      FROM Series s 
      LEFT JOIN Profile p ON s.profile_id = p.id
    ''');
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
    
    String accessoryCategory = 'أخرى';
    final List<String> categories = ['مقبض', 'فيرو', 'مفاصل', 'إسبانيوليت', 'قاش', 'قفل', 'الطاسو', 'البراغي', 'سيستم أو بي', 'فيرو سنترال', 'أخرى'];
    
    String quality = 'جودة قياسية';
    final List<String> qualities = ['جودة رفيعة', 'جودة قياسية', 'جودة تجارية'];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('إضافة أكسسوار جديد', Provider.of<AppSettingsProvider>(context).language),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl, 
                  decoration: InputDecoration(
                    labelText: Localization.translate('اسم الأكسسوار (مثال: مقبض إيطالي)', Provider.of<AppSettingsProvider>(context).language)
                  )
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: accessoryCategory,
                  items: categories.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      accessoryCategory = newValue!;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'تصنيف الإكسسوار (النوع)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: quality,
                  items: qualities.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      quality = newValue!;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'الجودة (النوعية)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: materialType,
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
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
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedSeriesId,
                    items: _series.where((s) => s['type'] == materialType).map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text("${s['profile_name'] ?? ''} - ${s['name']}"),
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
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  String finalName = "${nameCtrl.text} ($quality)";
                  String finalType = "$accessoryCategory|$quality";
                  
                  await widget.db.insertAccessory({
                    'name': finalName,
                    'material_type': materialType,
                    'scope': scope,
                    'series_id': scope == 'Unique' ? selectedSeriesId : null,
                    'type': finalType, 
                    'price': 0.0 
                  });
                  _loadItems();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    // Attempt to extract raw name without quality if it was appended
    String rawName = item['name']?.toString() ?? '';
    rawName = rawName.replaceAll(RegExp(r'\s*\((جودة رفيعة|جودة قياسية|جودة تجارية)\)$'), '');
    
    final nameCtrl = TextEditingController(text: rawName);
    String materialType = item['material_type']?.toString() ?? 'Aluminium';
    String scope = item['scope']?.toString() ?? 'Global';
    int? selectedSeriesId = item['series_id'] as int?;

    // Decode Type and Quality
    String accessoryCategory = 'أخرى';
    String quality = 'جودة قياسية';
    String dbType = item['type']?.toString() ?? '';
    final List<String> categories = ['مقبض', 'فيرو', 'مفاصل', 'إسبانيوليت', 'قاش', 'قفل', 'الطاسو', 'البراغي', 'سيستم أو بي', 'فيرو سنترال', 'أخرى'];
    final List<String> qualities = ['جودة رفيعة', 'جودة قياسية', 'جودة تجارية'];
    
    if (dbType.contains('|')) {
      var parts = dbType.split('|');
      if (categories.contains(parts[0])) accessoryCategory = parts[0];
      if (parts.length > 1 && qualities.contains(parts[1])) quality = parts[1];
    } else {
      // Legacy data parsing
      if (categories.contains(dbType)) accessoryCategory = dbType;
    }

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('تعديل', Provider.of<AppSettingsProvider>(context).language),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: nameCtrl, 
                  decoration: InputDecoration(labelText: Localization.translate('اسم الأكسسوار', Provider.of<AppSettingsProvider>(context).language))
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: accessoryCategory,
                  items: categories.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      accessoryCategory = newValue!;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'تصنيف الإكسسوار (النوع)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: quality,
                  items: qualities.map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      quality = newValue!;
                    });
                  },
                  decoration: const InputDecoration(labelText: 'الجودة (النوعية)'),
                ),
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: materialType,
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
                const SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
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
                  const SizedBox(height: 10),
                  DropdownButtonFormField<int>(
                    initialValue: selectedSeriesId,
                    items: _series.where((s) => s['type'] == materialType).map((s) {
                      return DropdownMenuItem<int>(
                        value: s['id'] as int,
                        child: Text("${s['profile_name'] ?? ''} - ${s['name']}"),
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
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language), style: const TextStyle(color: Colors.grey)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blue),
              onPressed: () async {
                if (nameCtrl.text.isNotEmpty) {
                  String finalName = "${nameCtrl.text} ($quality)";
                  String finalType = "$accessoryCategory|$quality";

                  await widget.db.updateAccessory(item['id'] as int, {
                    'name': finalName,
                    'material_type': materialType,
                    'scope': scope,
                    'series_id': scope == 'Unique' ? selectedSeriesId : null,
                    'type': finalType,
                  });
                  _loadItems();
                  if (context.mounted) Navigator.pop(context);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language), style: const TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;
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
                      style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(subtitle),
                        if (item['type'] != null && item['type'].toString().contains('|'))
                          Text(
                            "النوع: ${item['type'].toString().split('|')[0]} | الجودة: ${item['type'].toString().split('|')[1]}",
                            style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                          ),
                      ],
                    ),
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
                            await widget.db.deleteAccessory(item['id'] as int);
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
