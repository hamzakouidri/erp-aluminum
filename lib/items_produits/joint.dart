import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class JointsScreen extends StatefulWidget {
  final SqlDatabase db;

  const JointsScreen({super.key, required this.db});

  @override
  State<JointsScreen> createState() => _JointsScreenState();
}

class _JointsScreenState extends State<JointsScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _series = [];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  Future<void> _loadItems() async {
    final items = await widget.db.readJoints();
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
    final thicknessCtrl = TextEditingController();
    final priceCtrl = TextEditingController();
    String materialType = 'Aluminium';
    String scope = 'Global';
    List<int> selectedSeriesIds = [];

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate(
              'إضافة جوان جديد',
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
                      'اسم الجوان',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
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
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'نوع المادة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  items: ['Global', 'Unique'].map((String value) {
                    String translatedValue = value == 'Global'
                        ? Localization.translate(
                            "عام لجميع السلاسل",
                            Provider.of<AppSettingsProvider>(context).language,
                          )
                        : Localization.translate(
                            "مخصص لسلاسل معينة",
                            Provider.of<AppSettingsProvider>(context).language,
                          );
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: materialType == 'PVC'
                      ? null
                      : (newValue) {
                          setStateDialog(() {
                            scope = newValue!;
                          });
                        },
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'النطاق',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                if (scope == 'Unique') ...[
                  SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    child: ExpansionTile(
                      title: Text(
                        Localization.translate(
                          'حدد السلاسل',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: _series.map((s) {
                        final sId = s['id'] as int;
                        return CheckboxListTile(
                          title: Text("${s['profile_name'] ?? ''} - ${s['name']}"),
                          value: selectedSeriesIds.contains(sId),
                          onChanged: (bool? val) {
                            setStateDialog(() {
                              if (val == true) {
                                selectedSeriesIds.add(sId);
                              } else {
                                selectedSeriesIds.remove(sId);
                              }
                            });
                          },
                        );
                      }).toList(),
                    ),
                  ),
                ],
                SizedBox(height: 10),
                TextField(
                  controller: thicknessCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'السماكة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
                TextField(
                  controller: priceCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'سعر المتر',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                  keyboardType: TextInputType.number,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
                  try {
                    final dbInstance = await widget.db.db;
                    await dbInstance!.insert('Joints', {
                      'name': nameCtrl.text,
                      'type': materialType,
                      'scope': scope,
                      'series_id': null,
                      'series_ids': scope == 'Unique'
                          ? selectedSeriesIds.join(',')
                          : null,
                      'thickness': double.tryParse(thicknessCtrl.text) ?? 0.0,
                      'price_per_meter': double.tryParse(priceCtrl.text) ?? 0.0,
                    });
                    _loadItems();
                    if (context.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
                      );
                    }
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
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item, bool isUserAdmin) {
    final nameCtrl = TextEditingController(text: item['name'].toString());
    final thicknessCtrl = TextEditingController(
      text: item['thickness'].toString(),
    );
    final priceCtrl = TextEditingController(
      text: item['price_per_meter'].toString(),
    );
    String materialType = item['type']?.toString() == 'PVC'
        ? 'PVC'
        : 'Aluminium';
    String scope = item['scope']?.toString() == 'Unique' ? 'Unique' : 'Global';

    List<int> selectedSeriesIds = [];
    if (item['series_ids'] != null &&
        item['series_ids'].toString().isNotEmpty) {
      selectedSeriesIds = item['series_ids']
          .toString()
          .split(',')
          .map((e) => int.tryParse(e) ?? -1)
          .where((e) => e != -1)
          .toList();
    } else if (item['series_id'] != null) {
      selectedSeriesIds = [item['series_id'] as int];
    }

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
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
                      'اسم الجوان',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: materialType,
                  items: ['Aluminium', 'PVC'].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                  onChanged: !isUserAdmin
                      ? null
                      : (newValue) {
                          setStateDialog(() {
                            materialType = newValue!;
                            if (materialType == 'PVC') {
                              scope = 'Global';
                            }
                          });
                        },
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'نوع المادة',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                DropdownButtonFormField<String>(
                  initialValue: scope,
                  items: ['Global', 'Unique'].map((String value) {
                    String translatedValue = value == 'Global'
                        ? Localization.translate(
                            "عام لجميع السلاسل",
                            Provider.of<AppSettingsProvider>(context).language,
                          )
                        : Localization.translate(
                            "مخصص لسلاسل معينة",
                            Provider.of<AppSettingsProvider>(context).language,
                          );
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(translatedValue),
                    );
                  }).toList(),
                  onChanged: (!isUserAdmin || materialType == 'PVC')
                      ? null
                      : (newValue) {
                          setStateDialog(() {
                            scope = newValue!;
                          });
                        },
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'النطاق',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                if (scope == 'Unique') ...[
                  SizedBox(height: 10),
                  Card(
                    elevation: 2,
                    child: ExpansionTile(
                      title: Text(
                        Localization.translate(
                          'حدد السلاسل',
                          Provider.of<AppSettingsProvider>(context).language,
                        ),
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      children: _series.map((s) {
                        final sId = s['id'] as int;
                        return CheckboxListTile(
                          title: Text("${s['profile_name'] ?? ''} - ${s['name']}"),
                          value: selectedSeriesIds.contains(sId),
                          onChanged: !isUserAdmin
                              ? null
                              : (bool? val) {
                                  setStateDialog(() {
                                    if (val == true) {
                                      selectedSeriesIds.add(sId);
                                    } else {
                                      selectedSeriesIds.remove(sId);
                                    }
                                  });
                                },
                        );
                      }).toList(),
                    ),
                  ),
                ],
                SizedBox(height: 10),
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
                      'سعر المتر',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
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
                  try {
                    final dbInstance = await widget.db.db;
                    await dbInstance!.update(
                      'Joints',
                      {
                        'name': nameCtrl.text,
                        'type': materialType,
                        'scope': scope,
                        'series_id': null,
                        'series_ids': scope == 'Unique'
                            ? selectedSeriesIds.join(',')
                            : null,
                        'thickness': double.tryParse(thicknessCtrl.text) ?? 0.0,
                        'price_per_meter':
                            double.tryParse(priceCtrl.text) ?? 0.0,
                      },
                      where: 'id = ?',
                      whereArgs: [item['id']],
                    );
                    _loadItems();
                    if (context.mounted) Navigator.pop(dialogContext);
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('حدث خطأ أثناء الحفظ: $e')),
                      );
                    }
                  }
                }
              },
              child: Text(
                Localization.translate(
                  'حفظ التعديل',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                style: TextStyle(color: Colors.white),
              ),
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
        title: Text(
          Localization.translate(
            'الجوانات / الجلدات',
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
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: Colors.blue,
                      ),
                    ),
                    subtitle: Text(
                      item['type'].toString().contains('PVC')
                          ? "PVC - عام"
                          : (item['scope'].toString() == 'Unique'
                                ? "مخصص لسيري معين"
                                : "عام لجميع السيريات"),
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          icon: Icon(Icons.edit, color: Colors.blue, size: 20),
                          onPressed: () => _showEditDialog(item, isUserAdmin),
                        ),
                        if (isUserAdmin)
                          IconButton(
                            icon: Icon(
                              Icons.delete,
                              color: Colors.red,
                              size: 20,
                            ),
                            onPressed: () async {
                              await widget.db.deleteJoint(item['id']);
                              _loadItems();
                            },
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: Icon(Icons.add),
            ),
    );
  }
}
