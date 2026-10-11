import 'dart:async';

import 'package:database_data/widgets/app_material.dart';

import '../sql_database.dart';
import '../services/cloud_sync_service.dart';

import 'package:database_data/settings/localization.dart';

import 'package:database_data/settings/app_settings.dart';

import 'package:provider/provider.dart';

import '../widgets/section_image.dart';

class JointsScreen extends StatefulWidget {
  final SqlDatabase db;

  const JointsScreen({super.key, required this.db});

  @override
  State<JointsScreen> createState() => _JointsScreenState();
}

class _JointsScreenState extends State<JointsScreen> {
  String searchQuery = '';
  StreamSubscription? _dbSubscription;

  List<Map<String, dynamic>> _items = [];

  List<Map<String, dynamic>> _series = [];

  @override
  void initState() {
    super.initState();

    _loadItems();
    _dbSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) _loadItems();
    });
  }

  @override
  void dispose() {
    _dbSubscription?.cancel();
    super.dispose();
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
    String selectedGasketType = 'جوان فيتراج';
    List<int> selectedSeriesIds = [];
    bool isSaving = false;

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
                  isExpanded: true,
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
                        selectedSeriesIds.clear();
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
                  isExpanded: true,
                  initialValue: selectedGasketType,
                  items:
                      [
                        'جوان بوراج',
                        'جوان فيتراج',
                        'جوان فراب',
                        'جوان سنترال',
                        'جوان براش',
                      ].map((String value) {
                        final lang = Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        ).language;
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(Localization.translate(value, lang)),
                        );
                      }).toList(),
                  onChanged: (newValue) {
                    setStateDialog(() {
                      selectedGasketType = newValue!;
                    });
                  },
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'نوع الجوان',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                if (materialType == 'Aluminium') ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: scope,
                    items: ['Global', 'Unique'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: (newValue) {
                      setStateDialog(() {
                        scope = newValue!;
                        if (scope == 'Global') {
                          selectedSeriesIds.clear();
                        }
                      });
                    },
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'النطاق',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                if (materialType == 'Aluminium' && scope == 'Unique') ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate(
                            'اختر السلاسل المسموح لها:',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Column(
                          children: _series
                              .where((s) {
                                final mat =
                                    s['material_type']?.toString() ?? '';
                                return mat == 'Aluminium' || mat.isEmpty;
                              })
                              .map((s) {
                                final sId =
                                    int.tryParse(s['id'].toString()) ?? -1;
                                if (sId == -1) return const SizedBox.shrink();
                                return CheckboxListTile(
                                  title: Text(
                                    "${s['profile_name'] ?? ''} - ${s['name']}",
                                  ),
                                  value: selectedSeriesIds.contains(sId),
                                  onChanged: (bool? checked) {
                                    setStateDialog(() {
                                      if (checked == true) {
                                        selectedSeriesIds.add(sId);
                                      } else {
                                        selectedSeriesIds.remove(sId);
                                      }
                                    });
                                  },
                                );
                              })
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
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
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameCtrl.text.isNotEmpty) {
                        if (materialType == 'Aluminium' &&
                            scope == 'Unique' &&
                            selectedSeriesIds.isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate(
                                  'يرجى اختيار سلسلة واحدة على الأقل عند تحديد النطاق الخاص',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        setStateDialog(() => isSaving = true);
                        try {
                          final dbInstance = await widget.db.db;
                          final seriesIdsStr =
                              (scope == 'Unique' &&
                                  selectedSeriesIds.isNotEmpty)
                              ? ',${selectedSeriesIds.join(',')},'
                              : null;
                          final seriesIdVal =
                              (scope == 'Unique' &&
                                  selectedSeriesIds.isNotEmpty)
                              ? selectedSeriesIds.first
                              : null;

                          final values = <String, dynamic>{
                            'name': nameCtrl.text,
                            'type': materialType,
                            'scope': scope,
                            'series_id': seriesIdVal,
                            'series_ids': seriesIdsStr,
                            'thickness':
                                double.tryParse(thicknessCtrl.text) ?? 0.0,
                            'price_per_meter':
                                double.tryParse(priceCtrl.text) ?? 0.0,
                            'gasket_type': selectedGasketType,
                          };
                          final insertedId = await dbInstance!.insert(
                            'Joints',
                            values,
                          );
                          // The direct detailed insert must still publish the
                          // catalog change so the other workshop devices receive it.
                          unawaited(CloudSyncService().notifyCatalogChange());

                          if (mounted) {
                            setState(() {
                              _items = [
                                ..._items,
                                <String, dynamic>{...values, 'id': insertedId},
                              ];
                            });
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'تم الحفظ بنجاح!',
                                    Provider.of<AppSettingsProvider>(
                                      context,
                                      listen: false,
                                    ).language,
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${Localization.translate('حدث خطأ أثناء الحفظ', Provider.of<AppSettingsProvider>(context, listen: false).language)}: $e',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      Localization.translate(
                        'حفظ',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: const TextStyle(color: Colors.white),
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
    String selectedGasketType =
        item['gasket_type']?.toString() ?? 'جوان فيتراج';
    bool isSaving = false;
    if (selectedGasketType.contains('بروس') ||
        selectedGasketType.contains('براش') ||
        selectedGasketType.toLowerCase().contains('brosse') ||
        selectedGasketType.toLowerCase().contains('brush')) {
      selectedGasketType = 'جوان براش';
    }

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
                  isExpanded: true,
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
                              selectedSeriesIds.clear();
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
                  isExpanded: true,
                  initialValue: selectedGasketType,
                  items:
                      [
                        'جوان بوراج',
                        'جوان فيتراج',
                        'جوان فراب',
                        'جوان سنترال',
                        'جوان براش',
                      ].map((String value) {
                        final lang = Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        ).language;
                        return DropdownMenuItem<String>(
                          value: value,
                          child: Text(Localization.translate(value, lang)),
                        );
                      }).toList(),
                  onChanged: !isUserAdmin
                      ? null
                      : (newValue) {
                          setStateDialog(() {
                            selectedGasketType = newValue!;
                          });
                        },
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'نوع الجوان',
                      Provider.of<AppSettingsProvider>(context).language,
                    ),
                  ),
                ),
                SizedBox(height: 10),
                if (materialType == 'Aluminium') ...[
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    initialValue: scope,
                    items: ['Global', 'Unique'].map((String value) {
                      return DropdownMenuItem<String>(
                        value: value,
                        child: Text(value),
                      );
                    }).toList(),
                    onChanged: !isUserAdmin
                        ? null
                        : (newValue) {
                            setStateDialog(() {
                              scope = newValue!;
                              if (scope == 'Global') {
                                selectedSeriesIds.clear();
                              }
                            });
                          },
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'النطاق',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  ),
                  SizedBox(height: 10),
                ],
                if (materialType == 'Aluminium' && scope == 'Unique') ...[
                  Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          Localization.translate(
                            'اختر السلاسل المسموح لها:',
                            Provider.of<AppSettingsProvider>(context).language,
                          ),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 5),
                        Column(
                          children: _series
                              .where((s) {
                                final mat =
                                    s['material_type']?.toString() ?? '';
                                return mat == 'Aluminium' || mat.isEmpty;
                              })
                              .map((s) {
                                final sId =
                                    int.tryParse(s['id'].toString()) ?? -1;
                                if (sId == -1) return const SizedBox.shrink();
                                return CheckboxListTile(
                                  title: Text(
                                    "${s['profile_name'] ?? ''} - ${s['name']}",
                                  ),
                                  value: selectedSeriesIds.contains(sId),
                                  onChanged: !isUserAdmin
                                      ? null
                                      : (bool? checked) {
                                          setStateDialog(() {
                                            if (checked == true) {
                                              selectedSeriesIds.add(sId);
                                            } else {
                                              selectedSeriesIds.remove(sId);
                                            }
                                          });
                                        },
                                );
                              })
                              .toList(),
                        ),
                      ],
                    ),
                  ),
                ],
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
              onPressed: isSaving
                  ? null
                  : () async {
                      if (nameCtrl.text.isNotEmpty) {
                        if (materialType == 'Aluminium' &&
                            scope == 'Unique' &&
                            selectedSeriesIds.isEmpty) {
                          ScaffoldMessenger.of(dialogContext).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate(
                                  'يرجى اختيار سلسلة واحدة على الأقل عند تحديد النطاق الخاص',
                                  Provider.of<AppSettingsProvider>(
                                    context,
                                  ).language,
                                ),
                              ),
                            ),
                          );
                          return;
                        }
                        setStateDialog(() => isSaving = true);
                        try {
                          final dbInstance = await widget.db.db;
                          final seriesIdsStr =
                              (scope == 'Unique' &&
                                  selectedSeriesIds.isNotEmpty)
                              ? ',${selectedSeriesIds.join(',')},'
                              : null;
                          final seriesIdVal =
                              (scope == 'Unique' &&
                                  selectedSeriesIds.isNotEmpty)
                              ? selectedSeriesIds.first
                              : null;

                          final values = <String, dynamic>{
                            'name': nameCtrl.text,
                            'type': materialType,
                            'scope': scope,
                            'series_id': seriesIdVal,
                            'series_ids': seriesIdsStr,
                            'thickness':
                                double.tryParse(thicknessCtrl.text) ?? 0.0,
                            'price_per_meter':
                                double.tryParse(priceCtrl.text) ?? 0.0,
                            'gasket_type': selectedGasketType,
                          };
                          final updatedRows = await dbInstance!.update(
                            'Joints',
                            values,
                            where: 'id = ?',
                            whereArgs: [item['id']],
                          );
                          if (updatedRows == 0) {
                            throw StateError('Joint row was not found');
                          }
                          unawaited(CloudSyncService().notifyCatalogChange());

                          if (mounted) {
                            setState(() {
                              final index = _items.indexWhere(
                                (row) => row['id'] == item['id'],
                              );
                              if (index >= 0) {
                                _items[index] = <String, dynamic>{
                                  ..._items[index],
                                  ...values,
                                };
                              }
                            });
                          }
                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'تم الحفظ بنجاح!',
                                    Provider.of<AppSettingsProvider>(
                                      context,
                                      listen: false,
                                    ).language,
                                  ),
                                ),
                              ),
                            );
                          }
                        } catch (e) {
                          if (dialogContext.mounted) {
                            setStateDialog(() => isSaving = false);
                          }
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  '${Localization.translate('حدث خطأ أثناء الحفظ', Provider.of<AppSettingsProvider>(context, listen: false).language)}: $e',
                                ),
                              ),
                            );
                          }
                        }
                      }
                    },
              child: isSaving
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: Colors.white,
                      ),
                    )
                  : Text(
                      Localization.translate(
                        'حفظ التعديل',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                      style: const TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,

      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'تأكيد الحذف',

          style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red),
        ),

        content: const Text(
          'سيتم أرشفة هذا العنصر (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',

          style: TextStyle(fontSize: 14),
        ),

        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),

            child: Text(
              Localization.translate(
                'إلغاء',
                Provider.of<AppSettingsProvider>(context).language,
              ),
            ),
          ),

          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),

            onPressed: () async {
              await widget.db.deleteJoint(item['id']);
              unawaited(CloudSyncService().notifyCatalogChange());

              _loadItems();

              if (context.mounted) Navigator.pop(dialogContext);
            },

            child: const Text(
              'موافق، قم بالأرشفة',

              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGasketCard(
    Map<String, dynamic> item,
    Color sectionColor,
    bool isUserAdmin,
  ) {
    final double thickness = (item['thickness'] ?? 0.0) is num
        ? (item['thickness'] as num).toDouble()
        : double.tryParse(item['thickness'].toString()) ?? 0.0;

    final double price = (item['price_per_meter'] ?? 0.0) is num
        ? (item['price_per_meter'] as num).toDouble()
        : double.tryParse(item['price_per_meter'].toString()) ?? 0.0;

    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final imageCode = _jointAssetCode(item, thickness);
    String subtitle = "${item['type']}";
    if (thickness > 0) {
      subtitle +=
          " - السماكة: ${thickness.toStringAsFixed(thickness.truncateToDouble() == thickness ? 0 : 1)} مم";
    }
    if (item['gasket_type'] != null &&
        item['gasket_type'].toString().isNotEmpty) {
      final String translatedGasketType = Localization.translate(
        item['gasket_type'].toString(),
        lang,
      );
      subtitle += " - النوع: $translatedGasketType";
    }
    subtitle +=
        " - السعر: ${price.toStringAsFixed(price.truncateToDouble() == price ? 0 : 2)} دج/m";

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),

      child: ListTile(
        leading: SectionImageWidget(
          code: imageCode,
          imagePath: item['image_path']?.toString(),
          name: item['name']?.toString(),
          size: 54,
          fallbackIcon: Icons.gesture,
        ),
        title: Text(
          item['name'].toString(),

          style: TextStyle(fontWeight: FontWeight.bold, color: sectionColor),
        ),

        subtitle: Text(subtitle),

        trailing: isUserAdmin
            ? Row(
                mainAxisSize: MainAxisSize.min,

                children: [
                  IconButton(
                    icon: const Icon(Icons.edit, color: Colors.blue),

                    onPressed: () => _showEditDialog(item, isUserAdmin),
                  ),

                  IconButton(
                    icon: const Icon(Icons.delete, color: Colors.red),

                    onPressed: () => _showDeleteDialog(item),
                  ),
                ],
              )
            : null,
      ),
    );
  }

  /// Resolves the bundled profile image for joints that historically had no
  /// code/image_path column. Bourrage joints use the catalogue codes 52034,
  /// 52035 and 52036 according to their nominal thickness.
  String? _jointAssetCode(Map<String, dynamic> item, double thickness) {
    final label = '${item['name'] ?? ''} ${item['gasket_type'] ?? ''}'
        .toLowerCase();

    // Joint Frappe always uses the canonical image supplied by the catalogue,
    // regardless of an old code or image name stored on the row.
    final isFrappe =
        (label.contains('فراب') ||
            label.contains('ضرب') ||
            label.contains('frappe')) &&
        (label.contains('جوان') || label.contains('joint'));
    if (isFrappe) return 'joint_frappe.png';

    final explicitCode = item['code']?.toString().trim() ?? '';
    if (explicitCode.isNotEmpty) return explicitCode;

    final isBrush =
        label.contains('بروس') ||
        label.contains('براش') ||
        label.contains('brosse') ||
        label.contains('brush') ||
        label.contains('bros');
    if (isBrush) return 'joint_brosse.png';

    final isVitrage =
        label.contains('فيتراج') ||
        label.contains('vitrage') ||
        label.contains('vitre') ||
        label.contains('glass');
    if (isVitrage) return 'joint_vitrage.png';

    final isBourrage =
        label.contains('بوراج') ||
        label.contains('bourrage') ||
        label.contains('barre-clouse') ||
        label.contains('barclose');
    if (!isBourrage) return null;

    if (thickness >= 5.0) return '52036';
    if (thickness >= 3.0) return '52035';
    return '52034';
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;

    // Filter items based on searchQuery
    final filteredItems = _items.where((item) {
      if (searchQuery.isEmpty) return true;
      final q = searchQuery.toLowerCase().trim();
      final name = (item['name'] ?? '').toString().toLowerCase();
      final thickness = (item['thickness'] ?? '').toString().toLowerCase();
      final type = (item['type'] ?? '').toString().toLowerCase();
      return name.contains(q) || thickness.contains(q) || type.contains(q);
    }).toList();

    // Build a map of seriesId -> list of joints, and a list of global joints
    final Map<int, List<Map<String, dynamic>>> uniqueGasketsBySeries = {};

    for (var joint in filteredItems) {
      final scope = joint['scope']?.toString() ?? 'Global';
      if (scope == 'Unique') {
        List<int> sIds = [];
        if (joint['series_ids'] != null &&
            joint['series_ids'].toString().isNotEmpty) {
          sIds = joint['series_ids']
              .toString()
              .split(',')
              .map((e) => int.tryParse(e) ?? -1)
              .where((e) => e != -1)
              .toList();
        } else if (joint['series_id'] != null) {
          sIds = [joint['series_id'] as int];
        }
        for (var sId in sIds) {
          uniqueGasketsBySeries.putIfAbsent(sId, () => []).add(joint);
        }
      }
    }

    final List<Map<String, dynamic>> seriesWithGaskets = _series
        .where((s) => uniqueGasketsBySeries.containsKey(s['id']))
        .toList();

    // Sort series alphabetically by profile name, then series name
    seriesWithGaskets.sort((a, b) {
      final aProfile = a['profile_name']?.toString() ?? '';
      final bProfile = b['profile_name']?.toString() ?? '';
      final aName = a['name']?.toString() ?? '';
      final bName = b['name']?.toString() ?? '';
      int comp = aProfile.compareTo(bProfile);
      if (comp != 0) return comp;
      return aName.compareTo(bName);
    });

    final List<Color> palette = [
      Colors.blue.shade800,
      Colors.teal.shade800,
      Colors.deepOrange.shade800,
      Colors.purple.shade800,
      Colors.pink.shade800,
      Colors.indigo.shade800,
      Colors.green.shade800,
      Colors.cyan.shade800,
      Colors.amber.shade900,
      Colors.brown.shade800,
      Colors.blueGrey.shade800,
      Colors.red.shade800,
    ];

    List<Widget> sections = [];
    int sectionIndex = 0;

    // 1. Flat Gaskets Section (Top Part: "قائمة الجوانت")
    final listSectionColor = Colors.blueGrey.shade700;
    sections.add(
      Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: Row(
          children: [
            Icon(Icons.format_list_bulleted, color: listSectionColor, size: 22),
            const SizedBox(width: 8),
            Text(
              Localization.translate(
                'قائمة الجوانت',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: listSectionColor,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Divider(
                color: listSectionColor.withValues(alpha: 0.4),
                thickness: 1.5,
              ),
            ),
            const SizedBox(width: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: listSectionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '${filteredItems.length}',
                style: TextStyle(
                  color: listSectionColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
            ),
          ],
        ),
      ),
    );

    for (var item in filteredItems) {
      sections.add(_buildGasketCard(item, listSectionColor, isUserAdmin));
    }

    // 2. Divider/Separator line (only added if there are series-specific gaskets to follow)
    if (seriesWithGaskets.isNotEmpty) {
      sections.add(
        const Padding(
          padding: EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
          child: Divider(thickness: 2, color: Colors.grey),
        ),
      );
    }

    // 3. Series-specific Gaskets Sections (Bottom Part)
    for (var s in seriesWithGaskets) {
      final sId = s['id'] as int;
      final items = uniqueGasketsBySeries[sId] ?? [];
      if (items.isEmpty) continue;

      final sectionColor = palette[sectionIndex % palette.length];
      final seriesName = "${s['profile_name'] ?? ''} - ${s['name']}";

      sections.add(
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
          child: Row(
            children: [
              Icon(Icons.folder_special, color: sectionColor, size: 22),
              const SizedBox(width: 8),
              Text(
                seriesName,
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  color: sectionColor,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Divider(
                  color: sectionColor.withValues(alpha: 0.4),
                  thickness: 1.5,
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: sectionColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '${items.length}',
                  style: TextStyle(
                    color: sectionColor,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ],
          ),
        ),
      );

      for (var item in items) {
        sections.add(_buildGasketCard(item, sectionColor, isUserAdmin));
      }
      sectionIndex++;
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(
          Localization.translate(
            'الجوانات / الجلدات',
            Provider.of<AppSettingsProvider>(context).language,
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              decoration: InputDecoration(
                hintText: Localization.translate(
                  'بحث...',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
                prefixIcon: const Icon(Icons.search),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
              onChanged: (val) {
                setState(() {
                  searchQuery = val;
                });
              },
            ),
          ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(
                      Localization.translate(
                        'لا توجد بيانات',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  )
                : filteredItems.isEmpty
                ? Center(
                    child: Text(
                      Localization.translate(
                        'لا توجد نتائج مطابقة',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
                    ),
                  )
                : ListView(children: sections),
          ),
        ],
      ),
      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              child: const Icon(Icons.add),
            ),
    );
  }
}
