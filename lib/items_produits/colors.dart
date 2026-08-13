import 'dart:async';

import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import '../sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
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
  Map<int, List<int>> _profileColorsMap = {};
  StreamSubscription<String>? _dbSubscription;
  Timer? _reloadDebounce;

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
  }

  DecorationImage? _getDecorationImageFromName(String name) {
    name = name.toLowerCase();

    if (name.contains('desert') ||
        name.contains('oak') ||
        name.contains('ديزر') ||
        name.contains('ديزير')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_d0.png'),
        fit: BoxFit.cover,
      );
    }

    if (name.contains('أنتيك') ||
        name.contains('antique') ||
        name.contains('انتيك')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_antique.png'),
        fit: BoxFit.cover,
      );
    }

    if (name.contains('فوبوا كلير') ||
        name.contains('clair') ||
        name.contains('خشبي فاتح')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_d0.png'),
        fit: BoxFit.cover,
      );
    }

    if (name.contains('خشبي داكن') ||
        name.contains('foncé') ||
        name.contains('dark')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture_dark.png'),
        fit: BoxFit.cover,
      );
    }

    if (name.contains('خشبي') ||
        name.contains('bois') ||
        name.contains('wood') ||
        name.contains('فوبوا')) {
      return const DecorationImage(
        image: AssetImage('assets/images/wood_texture.png'),
        fit: BoxFit.cover,
      );
    }

    return null;
  }

  LinearGradient _getGradientFromName(String name, [String? hexCode]) {
    name = name.toLowerCase();

    if (name.contains('9007')) {
      return const LinearGradient(
        colors: [Color(0xFFB8C0C8), Color(0xFF8A939E), Color(0xFF606A75)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    // Check standard colors first to preserve their beautiful, handcrafted gradients
    if (name.contains('خام') || name.contains('brut') || name.contains('raw')) {
      return LinearGradient(
        colors: [Colors.grey.shade300, Colors.grey.shade500],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أبيض') ||
        name.contains('blanc') ||
        name.contains('white')) {
      return LinearGradient(
        colors: [Colors.white, Colors.grey.shade300],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أسود') ||
        name.contains('noir') ||
        name.contains('black')) {
      return LinearGradient(
        colors: [Colors.grey.shade800, Colors.black],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أصفر') ||
        name.contains('jaune') ||
        name.contains('yellow')) {
      return LinearGradient(
        colors: [Colors.orange.shade100, Colors.orange.shade300],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('بني') ||
        name.contains('marron') ||
        name.contains('brown')) {
      return LinearGradient(
        colors: [Colors.brown.shade400, Colors.brown.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('رمادي') ||
        name.contains('gris') ||
        name.contains('gray')) {
      return LinearGradient(
        colors: [Colors.grey.shade500, Colors.grey.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('بيج') || name.contains('beige')) {
      return const LinearGradient(
        colors: [Color(0xFFF5F5DC), Color(0xFFDCDCB4)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أزرق') ||
        name.contains('ازرق') ||
        name.contains('bleu') ||
        name.contains('blue')) {
      return LinearGradient(
        colors: [Colors.blue.shade400, Colors.blue.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أخضر') ||
        name.contains('اخضر') ||
        name.contains('vert') ||
        name.contains('green')) {
      return LinearGradient(
        colors: [Colors.green.shade400, Colors.green.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('أحمر') ||
        name.contains('احمر') ||
        name.contains('rouge') ||
        name.contains('red')) {
      return LinearGradient(
        colors: [Colors.red.shade400, Colors.red.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('ذهبي') ||
        name.contains('doré') ||
        name.contains('gold')) {
      return const LinearGradient(
        colors: [Color(0xFFF1D675), Color(0xFFD4AF37), Color(0xFF9C7616)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('فضي') ||
        name.contains('argent') ||
        name.contains('silver')) {
      return const LinearGradient(
        colors: [Color(0xFFC0C0C0), Color(0xFF808080)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('شامبانيا') ||
        name.contains('شامبان') ||
        name.contains('شمبان') ||
        name.contains('champagne')) {
      return const LinearGradient(
        colors: [Color(0xFFFFF4DF), Color(0xFFF7E7CE), Color(0xFFC9AE86)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }
    if (name.contains('خشبي') ||
        name.contains('bois') ||
        name.contains('wood')) {
      // For "Wood", a deeper gradient of browns.
      return LinearGradient(
        colors: [Colors.brown.shade300, Colors.brown.shade800],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
    }

    // Dynamic gradient calculation for custom colors added to the database
    if (hexCode != null && hexCode.trim().isNotEmpty) {
      String cleanHex = hexCode.trim().replaceAll('#', '');
      if (cleanHex.length == 6) {
        cleanHex = 'FF$cleanHex';
      }
      final intVal = int.tryParse(cleanHex, radix: 16);
      if (intVal != null) {
        final color = Color(intVal);
        final hsl = HSLColor.fromColor(color);
        final double lightnessDiff = 0.15;
        final light = hsl
            .withLightness((hsl.lightness + lightnessDiff).clamp(0.0, 1.0))
            .toColor();
        final dark = hsl
            .withLightness((hsl.lightness - lightnessDiff).clamp(0.0, 1.0))
            .toColor();
        return LinearGradient(
          colors: [light, dark],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        );
      }
    }

    return LinearGradient(colors: [Colors.grey.shade200, Colors.grey.shade300]);
  }

  void _showAddDialog() {
    TextEditingController nameCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
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
            onPressed: () async {
              String newName = nameCtrl.text.trim();
              if (newName.isNotEmpty) {
                String type = 'مخصص';
                String cName = newName.toLowerCase();
                if (cName.contains('أبيض') ||
                    cName.contains('ابيض') ||
                    cName.contains('blanc') ||
                    cName.contains('white')) {
                  type = 'Global';
                }
                await widget.db.insertColor(newName, "#FFFFFF", type);
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
    int? selectedProfileId = _profiles.isNotEmpty
        ? _profiles.first['id'] as int
        : null;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setStateDialog) => AlertDialog(
          title: Text(
            Localization.translate(
              'تخصيص الألوان حسب البروفيلات',
              Provider.of<AppSettingsProvider>(context).language,
            ),
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
          ),
          content: SizedBox(
            width: double.maxFinite,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_profiles.isNotEmpty)
                  DropdownButtonFormField<int>(
                    decoration: InputDecoration(
                      labelText: Localization.translate(
                        'اختر البروفيل',
                        Provider.of<AppSettingsProvider>(context).language,
                      ),
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
                        bool isChecked =
                            _profileColorsMap[selectedProfileId]?.contains(
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
                          onChanged: (bool? val) async {
                            final profileId = selectedProfileId;
                            if (profileId == null) return;
                            await widget.db.setColorForProfile(
                              profileId: profileId,
                              colorId: cId,
                              enabled: val == true,
                            );

                            setStateDialog(() {
                              if (val == true) {
                                if (!_profileColorsMap.containsKey(profileId)) {
                                  _profileColorsMap[profileId] = [];
                                }
                                _profileColorsMap[profileId]!.add(cId);
                              } else {
                                _profileColorsMap[profileId]?.remove(cId);
                              }
                            });
                            _loadItems();
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
              child: Text(
                Localization.translate(
                  'إغلاق',
                  Provider.of<AppSettingsProvider>(context).language,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showCustomizeGlassDialog() async {
    final glasses = await widget.db.readGlass();

    if (!mounted) return;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setStateDialog) {
          return AlertDialog(
            title: Text(
              Localization.translate(
                'تخصيص ألوان الزجاج',
                Provider.of<AppSettingsProvider>(context).language,
              ),
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
                              title: Text('ألوان $gName'),
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
                                  child: const Text(
                                    'إلغاء',
                                    style: TextStyle(color: Colors.grey),
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
                                      if (val == true) {
                                        final sh = shutterComponents.firstWhere(
                                          (s) => s['id'] == selectedShutId,
                                        );
                                        final basePrice = (sh['price'] is num)
                                            ? (sh['price'] as num).toDouble()
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
                                          shutColorMap[selectedShutId]?.remove(
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

  void _showDeleteDialog(Map<String, dynamic> item) {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          'تأكيد الحذف',
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.red,
          ),
        ),
        content: Text(
          'سيتم أرشفة هذا اللون (إخفاؤه) ولن يتم حذفه نهائياً حفاظاً على سلامة بيانات المخزون والفواتير السابقة المرتبطة به.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('إلغاء'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () async {
              await widget.db.deleteColor(item['id']);
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
