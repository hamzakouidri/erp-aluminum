import 'dart:async';

import 'package:database_data/widgets/app_material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import 'package:database_data/utils/real_color_resolver.dart';

class ColorsScreen extends StatefulWidget {
  final SqlDatabase db;

  const ColorsScreen({super.key, required this.db});

  @override
  State<ColorsScreen> createState() => _ColorsScreenState();
}

class _ColorsScreenState extends State<ColorsScreen> {
  List<Map<String, dynamic>> _items = [];
  List<Map<String, dynamic>> _profiles = [];
  Map<int, List<int>> _profileColorsMap = {};
  StreamSubscription<String>? _dbSubscription;
  Timer? _reloadDebounce;
  bool _loadingItems = false;
  bool _itemsReloadQueued = false;

  @override
  void initState() {
    super.initState();
    _loadItems();
    _dbSubscription = CloudSyncService().dbUpdateStream.listen((_) {
      _reloadDebounce?.cancel();
      _reloadDebounce = Timer(const Duration(milliseconds: 250), () {
        if (mounted) _loadItems();
      });
    });
  }

  @override
  void dispose() {
    _reloadDebounce?.cancel();
    _dbSubscription?.cancel();
    super.dispose();
  }

  Future<void> _loadItems() async {
    if (_loadingItems) {
      _itemsReloadQueued = true;
      return;
    }
    _loadingItems = true;
    try {
      do {
        _itemsReloadQueued = false;
        await widget.db.ensureProfileColorDefaults();
        final items = await widget.db.readColors();
        final profiles = await widget.db.readProfile();
        final dbInstance = await widget.db.db;

        Map<int, List<int>> pcMap = {};
        if (dbInstance != null) {
          try {
            final pcData = await dbInstance.query('ProfileColors');
            for (var row in pcData) {
              int pId = row['profile_id'] as int;
              int cId = row['color_id'] as int;
              if (!pcMap.containsKey(pId)) pcMap[pId] = [];
              pcMap[pId]!.add(cId);
            }
          } catch (e) {
            debugPrint('Error reading ProfileColors: $e');
          }
        }

        if (mounted) {
          setState(() {
            _items = items.map((e) => Map<String, dynamic>.from(e)).toList();
            _profiles = profiles;
            _profileColorsMap = pcMap;
          });
        }
      } while (_itemsReloadQueued && mounted);
    } finally {
      _loadingItems = false;
    }
  }

  bool _isShutterGreyBaseColor(Map<String, dynamic> color) {
    final name = (color['name'] ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_\-]+'), '')
        .replaceAll('ى', 'ي');
    return const {'grey', 'gray', 'gris', 'رمادي'}.contains(name);
  }

  DecorationImage? _getDecorationImageFromName(String name) {
    return realColorTextureImage({'name': name});
  }

  LinearGradient _getGradientFromName(String name, [String? hexCode]) {
    return LinearGradient(
      colors: realGradientColors({'name': name, 'hex_code': hexCode}),
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    );
  }

  void _showAddDialog() {
    TextEditingController nameCtrl = TextEditingController();
    var saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) => AlertDialog(
          title: Text(
            Localization.translate(
              'إضافة لون جديد',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          content: TextField(
            controller: nameCtrl,
            decoration: InputDecoration(
              labelText: Localization.translate(
                'اسم اللون',
                Provider.of<AppSettingsProvider>(context).language,
              ),
              border: const OutlineInputBorder(),
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
              ),
            ),
            ElevatedButton(
              onPressed: saving
                  ? null
                  : () async {
                      String newName = nameCtrl.text.trim();
                      if (newName.isNotEmpty) {
                        setDialogState(() => saving = true);
                        String type = 'مخصص';
                        String cName = newName.toLowerCase();
                        if (cName.contains('أبيض') ||
                            cName.contains('ابيض') ||
                            cName.contains('blanc') ||
                            cName.contains('white')) {
                          type = 'Global';
                        }
                        await widget.db.insertColor(
                          newName,
                          "#FFFFFF",
                          type,
                          notifySync: false,
                        );
                        await _loadItems();
                        unawaited(CloudSyncService().notifyCatalogChange());
                        if (context.mounted) Navigator.pop(dialogContext);
                      }
                    },
              child: Text(
                Localization.translate(
                  'حفظ',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showEditDialog(Map<String, dynamic> item) {
    TextEditingController nameCtrl = TextEditingController(
      text: Localization.translate(
        item['name'].toString().trim(),
        Provider.of<AppSettingsProvider>(context, listen: false).language,
      ),
    );

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          Localization.translate(
            'تعديل اسم اللون',
            Provider.of<AppSettingsProvider>(context).language,
          ),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: TextField(
          controller: nameCtrl,
          decoration: InputDecoration(
            labelText: Localization.translate(
              'اسم اللون',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            border: const OutlineInputBorder(),
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
            ),
          ),
          ElevatedButton(
            onPressed: () async {
              String newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                await widget.db.updateColor(
                  item['id'],
                  newName,
                  item['hex_code'].toString(),
                  item['type'].toString(),
                );
                _loadItems();
                if (context.mounted) Navigator.pop(dialogContext);
              }
            },
            child: Text(
              Localization.translate(
                'حفظ',
                Provider.of<AppSettingsProvider>(context).language,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showCustomizeDialog() {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    int? selectedProfileId = _profiles.isNotEmpty
        ? _profiles.first['id'] as int
        : null;
    final workingProfileColors = <int, Set<int>>{
      for (final entry in _profileColorsMap.entries)
        entry.key: entry.value.toSet(),
    };
    final changedProfileIds = <int>{};
    var saving = false;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate('تخصيص الألوان حسب البروفيلات', lang),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          titlePadding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Text(
                    Localization.translate(
                      'اختر الألوان الخاصة بكل بروفيل ثم اضغط حفظ وإغلاق.',
                      lang,
                    ),
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).textTheme.bodySmall?.color,
                    ),
                    textDirection: TextDirection.rtl,
                  ),
                ),
                const SizedBox(height: 12),
                if (_profiles.isNotEmpty)
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: Localization.translate('اختر البروفيل', lang),
                      border: const OutlineInputBorder(),
                    ),
                    initialValue: selectedProfileId,
                    items: _profiles.map((p) {
                      return DropdownMenuItem<int>(
                        value: p['id'] as int,
                        child: Text(
                          p['name'].toString(),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      );
                    }).toList(),
                    onChanged: (val) {
                      setStateDialog(() {
                        selectedProfileId = val;
                      });
                    },
                  ),
                const SizedBox(height: 15),
                if (selectedProfileId != null)
                  Expanded(
                    child: ListView.builder(
                      shrinkWrap: true,
                      itemCount: _items.length,
                      itemBuilder: (context, index) {
                        final color = _items[index];
                        final cId = color['id'] as int;
                        final isChecked =
                            workingProfileColors[selectedProfileId]?.contains(
                              cId,
                            ) ??
                            false;

                        return CheckboxListTile(
                          title: Text(
                            color['name'].toString(),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          secondary: Container(
                            width: 30,
                            height: 30,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _getGradientFromName(
                                color['name'].toString(),
                                color['hex_code']?.toString(),
                              ),
                              image: _getDecorationImageFromName(
                                color['name'].toString(),
                              ),
                              border: Border.all(color: Colors.grey.shade400),
                            ),
                          ),
                          value: isChecked,
                          onChanged: (bool? val) {
                            final profileId = selectedProfileId;
                            if (profileId == null) return;
                            setStateDialog(() {
                              final selectedColors = workingProfileColors
                                  .putIfAbsent(profileId, () => <int>{});
                              if (val == true) {
                                selectedColors.add(cId);
                              } else {
                                selectedColors.remove(cId);
                              }
                              changedProfileIds.add(profileId);
                            });
                          },
                        );
                      },
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(Localization.translate('إلغاء', lang)),
            ),
            ElevatedButton.icon(
              icon: const Icon(Icons.save_rounded, size: 18),
              label: Text(Localization.translate('حفظ وإغلاق', lang)),
              onPressed: saving
                  ? null
                  : () async {
                      final navigator = Navigator.of(dialogContext);
                      final messenger = ScaffoldMessenger.of(context);
                      setStateDialog(() => saving = true);
                      try {
                        final profilesToSave = <int>{...changedProfileIds};
                        final currentProfileId = selectedProfileId;
                        if (currentProfileId != null) {
                          profilesToSave.add(currentProfileId);
                        }
                        for (final profileId in profilesToSave) {
                          await widget.db.setColorsForProfile(
                            profileId,
                            workingProfileColors[profileId] ?? const <int>{},
                            notifySync: false,
                          );
                        }
                        for (final profileId in profilesToSave) {
                          final expected =
                              workingProfileColors[profileId] ?? const <int>{};
                          final saved = await widget.db.getColorIdsForProfile(
                            profileId,
                          );
                          if (saved.length != expected.length ||
                              !saved.containsAll(expected)) {
                            throw StateError(
                              'لم تتطابق ألوان البروفيل المحفوظة مع الاختيار.',
                            );
                          }
                        }
                        // Saving several profiles is one catalogue operation. A
                        // sync per profile starts overlapping uploads and reloads,
                        // which can freeze the Windows UI on larger catalogues.
                        unawaited(CloudSyncService().notifyCatalogChange());
                        await _loadItems();
                        if (!mounted) return;
                        navigator.pop();
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate(
                                'تم حفظ تخصيص ألوان البروفيلات بنجاح.',
                                lang,
                              ),
                            ),
                          ),
                        );
                      } catch (error) {
                        if (!mounted) return;
                        setStateDialog(() => saving = false);
                        messenger.showSnackBar(
                          SnackBar(
                            content: Text(
                              '${Localization.translate('تعذر حفظ تخصيص الألوان', lang)}: $error',
                            ),
                            backgroundColor: Colors.red,
                          ),
                        );
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomizeGlassDialog() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final glasses = await widget.db.readGlass();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              Localization.translate('تخصيص ألوان الزجاج', lang),
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: glasses.length,
                itemBuilder: (context, index) {
                  final glass = glasses[index];
                  final gId = glass['id'] as int;
                  final gName = glass['name'].toString();
                  final gType = glass['type'].toString();

                  String displayType = gType;
                  if (gType == 'Glass') {
                    displayType = 'زجاج';
                  } else if (gType == 'Intercall')
                    displayType = 'إنتركال';
                  else if (gType == 'Gas')
                    displayType = 'غاز';
                  else if (gType == 'Panneau')
                    displayType = 'بانو';
                  else if (gType == 'Baguette')
                    displayType = 'باجيت';
                  else if (gType == 'Rosette')
                    displayType = 'وردة';

                  final colorsStr = glass['color']?.toString() ?? '';
                  final count = colorsStr.isEmpty
                      ? 0
                      : colorsStr.split(',').length;

                  return ListTile(
                    title: Text(
                      gName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    subtitle: Text(
                      '$displayType | ${glass['thickness']} مم | الألوان المخصصة: $count',
                      style: const TextStyle(fontSize: 12),
                    ),
                    trailing: const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 16,
                    ),
                    onTap: () async {
                      final selectedColors = colorsStr
                          .split(',')
                          .map((c) => c.trim())
                          .where((c) => c.isNotEmpty)
                          .toSet();

                      await showDialog(
                        context: context,
                        builder: (subContext) => StatefulBuilder(
                          builder: (context, setStateSub) {
                            return AlertDialog(
                              title: Text(
                                '${Localization.translate('ألوان', lang)} $gName',
                              ),
                              content: SizedBox(
                                width: double.maxFinite,
                                child: ListView.builder(
                                  shrinkWrap: true,
                                  itemCount: _items.length,
                                  itemBuilder: (context, idx) {
                                    final color = _items[idx];
                                    final cName = color['name'].toString();
                                    final isChecked = selectedColors.contains(
                                      cName,
                                    );

                                    return CheckboxListTile(
                                      title: Text(cName),
                                      secondary: Container(
                                        width: 24,
                                        height: 24,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          gradient: _getGradientFromName(
                                            cName,
                                            color['hex_code']?.toString(),
                                          ),
                                          border: Border.all(
                                            color: Colors.grey.shade400,
                                          ),
                                        ),
                                      ),
                                      value: isChecked,
                                      onChanged: (bool? val) {
                                        setStateSub(() {
                                          if (val == true) {
                                            selectedColors.add(cName);
                                          } else {
                                            selectedColors.remove(cName);
                                          }
                                        });
                                      },
                                    );
                                  },
                                ),
                              ),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(subContext),
                                  child: Text(
                                    Localization.translate('إلغاء', lang),
                                    style: const TextStyle(color: Colors.grey),
                                  ),
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: Colors.blue,
                                  ),
                                  onPressed: () async {
                                    try {
                                      final newColorsStr = selectedColors.join(
                                        ',',
                                      );
                                      await widget.db.updateGlass(
                                        gId,
                                        glass['name']?.toString() ?? '',
                                        glass['type']?.toString() ?? '',
                                        (glass['thickness'] as num?)
                                                ?.toDouble() ??
                                            0.0,
                                        (glass['price_per_sqm'] as num?)
                                                ?.toDouble() ??
                                            0.0,
                                        color: newColorsStr,
                                        imagePath:
                                            glass['image_path']?.toString() ??
                                            '',
                                        subtype:
                                            glass['subtype']?.toString() ?? '',
                                        height:
                                            (glass['height'] as num?)
                                                ?.toDouble() ??
                                            0.0,
                                        visibleWidth:
                                            (glass['visible_width'] as num?)
                                                ?.toDouble(),
                                      );
                                      final updatedGlasses = await widget.db
                                          .readGlass();
                                      setStateDialog(() {
                                        glasses.clear();
                                        glasses.addAll(updatedGlasses);
                                      });
                                      Navigator.pop(subContext);
                                    } catch (e) {
                                      print(
                                        "Error saving glass color customisation: $e",
                                      );
                                    }
                                  },
                                  child: const Text(
                                    'حفظ',
                                    style: TextStyle(color: Colors.white),
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: Text(
                  Localization.translate(
                    'إغلاق',
                    Provider.of<AppSettingsProvider>(context).language,
                  ),
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _showCustomizeAccessoryColorsDialog() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final dbInstance = await widget.db.db;
    if (dbInstance == null) return;

    final accessories = await widget.db.readAccessories();
    final acpData = await dbInstance.query('AccessoryColorPrices');
    Map<int, Set<int>> accColorMap = {};
    for (var row in acpData) {
      int aId = row['accessory_id'] as int;
      int cId = row['color_id'] as int;
      if (!accColorMap.containsKey(aId)) accColorMap[aId] = {};
      accColorMap[aId]!.add(cId);
    }

    int? selectedAccId;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        String searchQuery = '';
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final aColors = selectedAccId != null
                ? (accColorMap[selectedAccId] ?? {})
                : <int>{};

            // Filter accessories by search query
            final filteredAccs = accessories.where((acc) {
              final name = acc['name'].toString().toLowerCase();
              return name.contains(searchQuery.toLowerCase());
            }).toList();

            // Ensure the currently selected item is in the list to avoid assertion errors
            if (selectedAccId != null &&
                !filteredAccs.any((acc) => acc['id'] == selectedAccId)) {
              final originalAcc = accessories.firstWhere(
                (acc) => acc['id'] == selectedAccId,
                orElse: () => {},
              );
              if (originalAcc.isNotEmpty) {
                filteredAccs.insert(0, originalAcc);
              }
            }

            return AlertDialog(
              title: Text(
                Localization.translate('تخصيص ألوان الإكسسوارات', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'بحث عن إكسسوار...',
                          lang,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                      ),
                      onChanged: (val) {
                        setStateDialog(() {
                          searchQuery = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Localization.translate(
                          'اختر الإكسسوار',
                          lang,
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      value: selectedAccId,
                      items: filteredAccs.map((acc) {
                        return DropdownMenuItem<int>(
                          value: acc['id'] as int,
                          child: Text(acc['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedAccId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selectedAccId == null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          Localization.translate(
                            'الرجاء اختيار إكسسوار أولاً لتخصيص ألوانه.',
                            lang,
                          ),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Expanded(
                        child: _items.isEmpty
                            ? Center(
                                child: Text(
                                  Localization.translate(
                                    'لا توجد ألوان.',
                                    lang,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _items.length,
                                itemBuilder: (cCtx, index) {
                                  final color = _items[index];
                                  final cId = color['id'] as int;
                                  final isMapped = aColors.contains(cId);
                                  return CheckboxListTile(
                                    title: Text(
                                      color['name'].toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    secondary: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: _getGradientFromName(
                                          color['name'].toString(),
                                          color['hex_code']?.toString(),
                                        ),
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                    value: isMapped,
                                    onChanged: (val) async {
                                      final db = await widget.db.db;
                                      if (db == null) return;
                                      if (val == true) {
                                        final acc = accessories.firstWhere(
                                          (a) => a['id'] == selectedAccId,
                                        );
                                        final basePrice = (acc['price'] is num)
                                            ? (acc['price'] as num).toDouble()
                                            : 0.0;
                                        await db.insert(
                                          'AccessoryColorPrices',
                                          {
                                            'accessory_id': selectedAccId,
                                            'color_id': cId,
                                            'price': basePrice,
                                          },
                                          conflictAlgorithm:
                                              ConflictAlgorithm.replace,
                                        );
                                        setStateDialog(() {
                                          accColorMap
                                              .putIfAbsent(
                                                selectedAccId!,
                                                () => {},
                                              )
                                              .add(cId);
                                        });
                                      } else {
                                        await db.delete(
                                          'AccessoryColorPrices',
                                          where:
                                              'accessory_id = ? AND color_id = ?',
                                          whereArgs: [selectedAccId, cId],
                                        );
                                        setStateDialog(() {
                                          accColorMap[selectedAccId]?.remove(
                                            cId,
                                          );
                                        });
                                      }
                                    },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showCustomizeShutterColorsDialog() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    await widget.db.ensureShutterComponentsUseGreyPrice();
    // The grey colour may have just been created during the migration; reload
    // the palette so it appears as the locked base-price row in this dialog.
    await _loadItems();
    if (!mounted) return;
    final dbInstance = await widget.db.db;
    if (dbInstance == null) return;

    final shutterComponents = await widget.db.readShutterComponents();
    final scpData = await dbInstance.query('ShutterColorPrices');
    Map<int, Set<int>> shutColorMap = {};
    for (var row in scpData) {
      int sId = row['shutter_component_id'] as int;
      int cId = row['color_id'] as int;
      if (!shutColorMap.containsKey(sId)) shutColorMap[sId] = {};
      shutColorMap[sId]!.add(cId);
    }

    int? selectedShutId;

    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (ctx, setStateDialog) {
            final sColors = selectedShutId != null
                ? (shutColorMap[selectedShutId] ?? {})
                : <int>{};
            return AlertDialog(
              title: Text(
                Localization.translate('تخصيص ألوان مركبات الستائر', lang),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DropdownButtonFormField<int>(
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر المكون', lang),
                        border: const OutlineInputBorder(),
                      ),
                      value: selectedShutId,
                      items: shutterComponents.map((sh) {
                        return DropdownMenuItem<int>(
                          value: sh['id'] as int,
                          child: Text(sh['name'].toString()),
                        );
                      }).toList(),
                      onChanged: (val) {
                        setStateDialog(() {
                          selectedShutId = val;
                        });
                      },
                    ),
                    const SizedBox(height: 12),
                    if (selectedShutId == null)
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          Localization.translate(
                            'الرجاء اختيار مكون أولاً لتخصيص ألوانه.',
                            lang,
                          ),
                          style: const TextStyle(color: Colors.grey),
                          textAlign: TextAlign.center,
                        ),
                      )
                    else
                      Expanded(
                        child: _items.isEmpty
                            ? Center(
                                child: Text(
                                  Localization.translate(
                                    'لا توجد ألوان.',
                                    lang,
                                  ),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _items.length,
                                itemBuilder: (cCtx, index) {
                                  final color = _items[index];
                                  final cId = color['id'] as int;
                                  final isMapped = sColors.contains(cId);
                                  final isGreyBaseColor =
                                      _isShutterGreyBaseColor(color);
                                  return CheckboxListTile(
                                    title: Text(
                                      isGreyBaseColor
                                          ? 'رمادي (السعر الأساسي)'
                                          : color['name'].toString(),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    secondary: Container(
                                      width: 30,
                                      height: 30,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: _getGradientFromName(
                                          color['name'].toString(),
                                          color['hex_code']?.toString(),
                                        ),
                                        border: Border.all(
                                          color: Colors.grey.shade400,
                                        ),
                                      ),
                                    ),
                                    value: isMapped,
                                    onChanged: isGreyBaseColor
                                        ? null
                                        : (val) async {
                                            if (val == true) {
                                              final sh = shutterComponents
                                                  .firstWhere(
                                                    (s) =>
                                                        s['id'] ==
                                                        selectedShutId,
                                                  );
                                              final basePrice =
                                                  (sh['price'] is num)
                                                  ? (sh['price'] as num)
                                                        .toDouble()
                                                  : 0.0;
                                              await widget.db
                                                  .setShutterColorForComponent(
                                                    shutterComponentId:
                                                        selectedShutId!,
                                                    colorId: cId,
                                                    enabled: true,
                                                    price: basePrice,
                                                  );
                                              setStateDialog(() {
                                                shutColorMap
                                                    .putIfAbsent(
                                                      selectedShutId!,
                                                      () => {},
                                                    )
                                                    .add(cId);
                                              });
                                            } else {
                                              await widget.db
                                                  .setShutterColorForComponent(
                                                    shutterComponentId:
                                                        selectedShutId!,
                                                    colorId: cId,
                                                    enabled: false,
                                                  );
                                              setStateDialog(() {
                                                shutColorMap[selectedShutId]
                                                    ?.remove(cId);
                                              });
                                            }
                                          },
                                    controlAffinity:
                                        ListTileControlAffinity.leading,
                                  );
                                },
                              ),
                      ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(Localization.translate('إغلاق', lang)),
                ),
              ],
            );
          },
        );
      },
    );
  }

  void _showDeleteDialog(Map<String, dynamic> item) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          Localization.translate('تأكيد الحذف', lang),
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          Localization.translate(
            'سيتم أرشفة هذا اللون (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
            lang,
          ),
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteColor(item['id']);
              _loadItems();
              if (context.mounted) Navigator.pop(dialogContext);
            },
            child: Text(
              Localization.translate('موافق، قم بالأرشفة', lang),
              style: const TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isUserAdmin = isAdmin;
    final lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      appBar: AppBar(title: Text(Localization.translate('الألوان', lang))),
      body: Column(
        children: [
          if (isUserAdmin)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              color: Theme.of(context).brightness == Brightness.dark
                  ? Theme.of(context).cardColor
                  : Colors.white,
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.blue.shade600,
                              foregroundColor: Colors.white,
                              side:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const BorderSide(
                                      color: Colors.white54,
                                      width: 1.2,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(
                              Icons.dashboard_customize,
                              size: 18,
                            ),
                            label: Text(
                              Localization.translate('تخصيص للزجاج', lang),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            onPressed: _showCustomizeGlassDialog,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.orange.shade600,
                              foregroundColor: Colors.white,
                              side:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const BorderSide(
                                      color: Colors.white54,
                                      width: 1.2,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.settings, size: 18),
                            label: Text(
                              Localization.translate('تخصيص البروفيل', lang),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            onPressed: _showCustomizeDialog,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.amber.shade700,
                              foregroundColor: Colors.white,
                              side:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const BorderSide(
                                      color: Colors.white54,
                                      width: 1.2,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.settings_suggest, size: 18),
                            label: Text(
                              Localization.translate('تخصيص الإكسسوارات', lang),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            onPressed: _showCustomizeAccessoryColorsDialog,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: SizedBox(
                          height: 46,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.deepPurple,
                              foregroundColor: Colors.white,
                              side:
                                  Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? const BorderSide(
                                      color: Colors.white54,
                                      width: 1.2,
                                    )
                                  : null,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                            icon: const Icon(Icons.settings_suggest, size: 18),
                            label: Text(
                              Localization.translate(
                                'تخصيص مركبات الستائر',
                                lang,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            onPressed: _showCustomizeShutterColorsDialog,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          Expanded(
            child: _items.isEmpty
                ? Center(
                    child: Text(Localization.translate('لا توجد بيانات', lang)),
                  )
                : ListView.builder(
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      return Card(
                        margin: EdgeInsets.all(8),
                        child: ListTile(
                          leading: Container(
                            width: 45,
                            height: 45,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              gradient: _getGradientFromName(
                                Localization.translate(
                                  item['name'].toString().trim(),
                                  lang,
                                ),
                                item['hex_code']?.toString(),
                              ),
                              image: _getDecorationImageFromName(
                                Localization.translate(
                                  item['name'].toString().trim(),
                                  lang,
                                ),
                              ),
                              border: Border.all(
                                color: Colors.grey.shade400,
                                width: 1,
                              ),
                              boxShadow: const [
                                BoxShadow(
                                  color: Colors.black12,
                                  blurRadius: 4,
                                  offset: Offset(0, 2),
                                ),
                              ],
                            ),
                          ),
                          title: Text(
                            Localization.translate(
                              item['name'].toString().trim(),
                              lang,
                            ),
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                          trailing: isUserAdmin
                              ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.edit,
                                        color: Colors.blue,
                                      ),
                                      onPressed: () => _showEditDialog(item),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.delete,
                                        color: Colors.red,
                                      ),
                                      onPressed: () => _showDeleteDialog(item),
                                    ),
                                  ],
                                )
                              : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: !isUserAdmin
          ? null
          : FloatingActionButton(
              onPressed: _showAddDialog,
              backgroundColor: Colors.blue.shade600,
              child: const Icon(Icons.add, color: Colors.white),
            ),
    );
  }
}
