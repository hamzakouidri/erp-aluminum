import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class ColorsScreen extends StatefulWidget {
  final SqlDatabase db;

  const ColorsScreen({super.key, required this.db});

  @override
  State<ColorsScreen> createState() => _ColorsScreenState();
}

class _ColorsScreenState extends State<ColorsScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _profiles = [];

  LinearGradient _getGradientFromName(String name) {
    name = name.toLowerCase();
    if (name.contains('أبيض') || name.contains('blanc') || name.contains('white')) {
      return LinearGradient(colors: [Colors.white, Colors.grey.shade300], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    if (name.contains('أسود') || name.contains('noir') || name.contains('black')) {
      return LinearGradient(colors: [Colors.grey.shade800, Colors.black], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    if (name.contains('أصفر') || name.contains('jaune') || name.contains('yellow')) {
      return LinearGradient(colors: [Colors.orange.shade100, Colors.orange.shade300], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    if (name.contains('بني') || name.contains('marron') || name.contains('brown')) {
      return LinearGradient(colors: [Colors.brown.shade400, Colors.brown.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    if (name.contains('رمادي') || name.contains('gris') || name.contains('gray')) {
      return LinearGradient(colors: [Colors.grey.shade500, Colors.grey.shade800], begin: Alignment.topLeft, end: Alignment.bottomRight);
    }
    return LinearGradient(colors: [Colors.grey.shade200, Colors.grey.shade300]);
  }

  final List<String> _baseColors = [
    "White", "Dark Grey", "Light Grey", "Black", "Wood", "Silver", "Champagne", "Bronze", "Beige"
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readColors();
    final profiles = await widget.db.readProfile();
    setState(() {
      _items = items;
      _profiles = profiles;
    });
  }

  void _showAddDialog() {
    String selectedColorKey = _baseColors.first;
    String selectedType = 'عام (Global)';
    List<int> selectedProfileIds = [];
    TextEditingController customColorController = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('إضافة لون جديد', Provider.of<AppSettingsProvider>(context).language),
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedColorKey,
                  items: [..._baseColors, 'أخرى (Other)'].map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key == 'أخرى (Other)' ? Localization.translate("Other", Provider.of<AppSettingsProvider>(context).language) : Localization.translate(key, Provider.of<AppSettingsProvider>(context).language)),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      selectedColorKey = newValue!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر اللون', Provider.of<AppSettingsProvider>(context).language),
                  ),
                ),
                if (selectedColorKey == 'أخرى (Other)') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: customColorController,
                    decoration: InputDecoration(
                      labelText: Localization.translate('اسم اللون الجديد', Provider.of<AppSettingsProvider>(context).language),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: ['عام (Global)', 'فريد (Unique)'].map((String value) {
                    String translatedValue = value.contains('عام') ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language) : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language);
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      selectedType = newValue!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: Localization.translate('النوع', Provider.of<AppSettingsProvider>(context).language),
                  ),
                ),
                if (selectedType == 'فريد (Unique)') ...[
                  SizedBox(height: 16),
                  Text(
                    Localization.translate('البروفيلات المسموحة:', Provider.of<AppSettingsProvider>(context).language),
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  ..._profiles.map((p) {
                    return CheckboxListTile(
                      title: Text(p['name'].toString()),
                      value: selectedProfileIds.contains(p['id']),
                      onChanged: (bool? val) {
                        setStateDialog(() {
                          if (val == true) {
                            selectedProfileIds.add(p['id']);
                          } else {
                            selectedProfileIds.remove(p['id']);
                          }
                        });
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language)),
            ),
            ElevatedButton(
              onPressed: () async {
                String newName = selectedColorKey == 'أخرى (Other)' 
                    ? customColorController.text.trim() 
                    : Localization.translate(selectedColorKey, Provider.of<AppSettingsProvider>(context, listen: false).language);
                
                if (newName.isNotEmpty) {
                  int colorId = await widget.db.insertColor(newName, "#FFFFFF", selectedType);
                  if (selectedType == 'فريد (Unique)') {
                    await widget.db.setProfilesForColor(colorId, selectedProfileIds);
                  }
                  _loadItems();
                  if (context.mounted) Navigator.pop(dialogContext);
                }
              },
              child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language)),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, bool isUserAdmin) async {
    String currentName = item['name'].toString();
    String selectedColorKey = _baseColors.firstWhere(
      (key) => Localization.translate(key, Provider.of<AppSettingsProvider>(context, listen: false).language) == currentName || key == currentName,
      orElse: () => 'أخرى (Other)'
    );

    String selectedType = item['type'].toString() == 'فريد (Unique)' || item['type'].toString() == 'Unique' ? 'فريد (Unique)' : 'عام (Global)';
    List<int> selectedProfileIds = await widget.db.getProfilesForColor(item['id']);
    TextEditingController customColorController = TextEditingController(text: selectedColorKey == 'أخرى (Other)' ? currentName : '');

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(Localization.translate('تعديل', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(fontWeight: FontWeight.bold)),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                DropdownButtonFormField<String>(
                  initialValue: selectedColorKey,
                  items: [..._baseColors, 'أخرى (Other)'].map((String key) {
                    return DropdownMenuItem<String>(
                      value: key,
                      child: Text(key == 'أخرى (Other)' ? Localization.translate("Other", Provider.of<AppSettingsProvider>(context).language) : Localization.translate(key, Provider.of<AppSettingsProvider>(context).language)),
                    );
                  }).toList(),
                  onChanged: isUserAdmin ? (newValue) {
                    setStateDialog(() {
                      selectedColorKey = newValue!;
                    });
                  } : null,
                  decoration: InputDecoration(
                    labelText: Localization.translate('اختر اللون', Provider.of<AppSettingsProvider>(context).language),
                  ),
                ),
                if (selectedColorKey == 'أخرى (Other)') ...[
                  SizedBox(height: 10),
                  TextField(
                    controller: customColorController,
                    readOnly: !isUserAdmin,
                    decoration: InputDecoration(
                      labelText: Localization.translate('اسم اللون', Provider.of<AppSettingsProvider>(context).language),
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: ['عام (Global)', 'فريد (Unique)'].map((String value) {
                    String translatedValue = value.contains('عام') ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language) : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language);
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: isUserAdmin ? (newValue) {
                    setStateDialog(() {
                      selectedType = newValue!;
                    });
                  } : null,
                  decoration: InputDecoration(
                    labelText: Localization.translate('النوع', Provider.of<AppSettingsProvider>(context).language),
                  ),
                ),
                if (selectedType == 'فريد (Unique)') ...[
                  SizedBox(height: 16),
                  Text(Localization.translate('البروفيلات المسموحة:', Provider.of<AppSettingsProvider>(context).language), style: TextStyle(fontWeight: FontWeight.bold)),
                  ..._profiles.map((p) {
                    return CheckboxListTile(
                      title: Text(p['name'].toString()),
                      value: selectedProfileIds.contains(p['id']),
                      onChanged: !isUserAdmin ? null : (bool? val) {
                        setStateDialog(() {
                          if (val == true) {
                            selectedProfileIds.add(p['id']);
                          } else {
                            selectedProfileIds.remove(p['id']);
                          }
                        });
                      },
                    );
                  }),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', Provider.of<AppSettingsProvider>(context).language)),
            ),
            if (isUserAdmin)
              ElevatedButton(
                onPressed: () async {
                  String newName = selectedColorKey == 'أخرى (Other)' 
                      ? customColorController.text.trim() 
                      : Localization.translate(selectedColorKey, Provider.of<AppSettingsProvider>(context, listen: false).language);
                  
                  if (newName.isNotEmpty) {
                    await widget.db.updateColor(item['id'], newName, "#FFFFFF", selectedType);
                    if (selectedType == 'فريد (Unique)') {
                      await widget.db.setProfilesForColor(item['id'], selectedProfileIds);
                    } else {
                      await widget.db.setProfilesForColor(item['id'], []);
                    }
                    _loadItems();
                    if (context.mounted) Navigator.pop(dialogContext);
                  }
                },
                child: Text(Localization.translate('حفظ', Provider.of<AppSettingsProvider>(context).language)),
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
        title: Text(Localization.translate('الألوان', Provider.of<AppSettingsProvider>(context).language)),
      ),
      body: _items.isEmpty
          ? Center(child: Text(Localization.translate('لا توجد بيانات', Provider.of<AppSettingsProvider>(context).language)))
          : ListView.builder(
              itemCount: _items.length,
              itemBuilder: (context, index) {
                final item = _items[index];
                return Card(
                  margin: EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  child: ListTile(
                    leading: Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        gradient: _getGradientFromName(item['name'].toString()),
                        border: Border.all(color: Colors.grey.shade400, width: 1),
                        boxShadow: [
                          BoxShadow(color: Colors.black12, blurRadius: 4, offset: Offset(0, 2))
                        ],
                      ),
                    ),
                    title: Text(
                      item['name'].toString(),
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.blue, fontSize: 16),
                    ),
                    subtitle: Text(item['type'].toString().contains('عام') ? Localization.translate("Global", Provider.of<AppSettingsProvider>(context).language) : Localization.translate("Unique (Per Series)", Provider.of<AppSettingsProvider>(context).language)),
                    trailing: !isUserAdmin ? null : Row(
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
                              await widget.db.deleteColor(item['id']);
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
