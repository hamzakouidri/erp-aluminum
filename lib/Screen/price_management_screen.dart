import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';

class PriceManagementScreen extends StatefulWidget {
  const PriceManagementScreen({super.key});

  @override
  State<PriceManagementScreen> createState() => _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen>
    with SingleTickerProviderStateMixin {
  final SqlDatabase db = SqlDatabase();
  bool get canChangePrices => Provider.of<AppSettingsProvider>(context, listen: false).canChangePrices();
  late TabController _tabController;

  List<Map<String, dynamic>> seriesList = [];
  List<Map<String, dynamic>> allColorList = [];
  List<Map<String, dynamic>> filteredColorListForSeries = [];
  List<Map<String, dynamic>> glassList = [];
  List<Map<String, dynamic>> shutterList = [];
  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> jointList = [];
  List<Map<String, dynamic>> sectionList = [];
  List<Map<String, dynamic>> profilesList = [];

  Map<int, Map<int, double>> seriesColorPrices = {};
  Map<int, Map<int, double>> sectionColorPrices = {};
  Map<int, Map<int, double>> accessoryColorPrices = {};
  Map<int, List<int>> profileColorsMap = {};

  bool isLoading = true;
  int? selectedAccessoryId;
  int? selectedSeriesId;
  int? selectedProfileId;
  int? selectedSeriesForSections;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 7, vsync: this);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final dbInstance = (await db.db)!;

    Future<List<Map<String, dynamic>>> safeQuery(String table) async {
      try {
        return await dbInstance.query(table);
      } catch (e) {
        print("Error loading $table: $e");
        // Robust fallback to create missing tables on the fly
        if (table == 'SeriesColorPrices') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS SeriesColorPrices (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              series_id INTEGER NOT NULL,
              color_id INTEGER NOT NULL,
              price REAL NOT NULL DEFAULT 0.0,
              UNIQUE(series_id, color_id)
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Colors') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Colors (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              hex_code TEXT NOT NULL,
              type TEXT NOT NULL DEFAULT 'Global',
              price REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
            await dbInstance.execute(
              'ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;',
            );
          } catch (e) {}
          return await dbInstance.query(table);
        } else if (table == 'Series') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Series (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              profile_id INTEGER NOT NULL,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price_per_meter REAL NOT NULL DEFAULT 0.0
            )
          ''');
          try {
            await dbInstance.execute(
              'ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;',
            );
          } catch (e) {}
          return await dbInstance.query(table);
        } else if (table == 'Glass') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Glass (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Shutters') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Shutters (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              color_id INTEGER,
              price_per_sqm REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Accessories') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Accessories (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              type TEXT NOT NULL,
              price REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        } else if (table == 'Joints') {
          await dbInstance.execute('''
            CREATE TABLE IF NOT EXISTS Joints (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              thickness REAL NOT NULL,
              price_per_meter REAL NOT NULL
            )
          ''');
          return await dbInstance.query(table);
        }
        return [];
      }
    }

    List<Map<String, dynamic>> sList = [];
    try {
      sList = await dbInstance.rawQuery('''
        SELECT 
          s.id, 
          s.profile_id, 
          s.name, 
          s.type, 
          s.price_per_meter,
          p.name as profile_name
        FROM Series s
        LEFT JOIN Profile p ON s.profile_id = p.id
      ''');
    } catch (e) {
      sList = await safeQuery('Series');
    }
    final cList = await safeQuery('Colors');
    final gList = await safeQuery('Glass');
    final shList = await safeQuery('ShutterComponents');
    final aList = await safeQuery('Accessories');
    final jList = await safeQuery('Joints');
    final secList = await safeQuery('Sections');
    final pList = await safeQuery('Profile');

    Map<int, Map<int, double>> tempPrices = {};
    Map<int, Map<int, double>> tempAccPrices = {};
    try {
      final pricesData = await safeQuery('SeriesColorPrices');
      for (var row in pricesData) {
        int sId = row['series_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempPrices.containsKey(sId)) {
          tempPrices[sId] = {};
        }
        tempPrices[sId]![cId] = p;
      }
    } catch (e) {
      print("Error parsing SeriesColorPrices: $e");
    }

    try {
      final accPricesData = await safeQuery('AccessoryColorPrices');
      for (var row in accPricesData) {
        int aId = row['accessory_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempAccPrices.containsKey(aId)) {
          tempAccPrices[aId] = {};
        }
        tempAccPrices[aId]![cId] = p;
      }
    } catch (e) {
      print("Error parsing AccessoryColorPrices: $e");
    }

    Map<int, Map<int, double>> tempSecPrices = {};
    try {
      final secPricesData = await safeQuery('SectionColorPrices');
      for (var row in secPricesData) {
        int secId = row['section_id'] as int;
        int cId = row['color_id'] as int;
        double p = (row['price'] as num).toDouble();
        if (!tempSecPrices.containsKey(secId)) {
          tempSecPrices[secId] = {};
        }
        tempSecPrices[secId]![cId] = p;
      }
    } catch (e) {
      print("Error parsing SectionColorPrices: $e");
    }

    Map<int, List<int>> tempProfColors = {};
    try {
      final pcData = await safeQuery('ProfileColors');
      for (var row in pcData) {
        int pId = row['profile_id'] as int;
        int cId = row['color_id'] as int;
        if (!tempProfColors.containsKey(pId)) {
          tempProfColors[pId] = [];
        }
        tempProfColors[pId]!.add(cId);
      }
    } catch (e) {
      print("Error parsing ProfileColors: $e");
    }

    if (!mounted) return;
    setState(() {
      seriesList = sList;
      allColorList = cList;
      glassList = gList;
      shutterList = shList;
      accessoryList = aList;
      jointList = jList;
      sectionList = secList;
      profilesList = pList;
      seriesColorPrices = tempPrices;
      accessoryColorPrices = tempAccPrices;
      sectionColorPrices = tempSecPrices;
      profileColorsMap = tempProfColors;

      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }
      if (seriesList.isNotEmpty && selectedSeriesForSections == null) {
        selectedSeriesForSections = seriesList.first['id'] as int;
      }
      if (profilesList.isNotEmpty && selectedProfileId == null) {
        selectedProfileId = profilesList.first['id'] as int;
      }
      if (accessoryList.isNotEmpty && selectedAccessoryId == null) {
        selectedAccessoryId = accessoryList.first['id'] as int;
      }

      isLoading = false;
    });
    await _updateFilteredColors();
  }

  Future<void> _updateFilteredColors() async {
    if (selectedSeriesId == null) return;
    final series = seriesList.firstWhere((s) => s['id'] == selectedSeriesId, orElse: () => {});
    if (series.isNotEmpty) {
      int profileId = series['profile_id'] as int;
      final filtered = await db.getColorsForProfile(profileId);
      if (mounted) {
        setState(() {
          filteredColorListForSeries = filtered;
        });
      }
    }
  }

  Future<void> _updatePrice(
    String table,
    int id,
    String column,
    double newPrice,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final dbInstance = (await db.db)!;
    await dbInstance.update(
      table,
      {column: newPrice},
      where: 'id = ?',
      whereArgs: [id],
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
        backgroundColor: Colors.green,
      ),
    );
    _loadAllData();
  }

  Future<void> _updateSeriesColorPrice(
    int seriesId,
    int colorId,
    double price,
  ) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    await db.setSeriesColorPrice(seriesId, colorId, price);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Widget _buildSeriesColorTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (seriesList.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لم يتم العثور على سلاسل. يرجى إضافة سلاسل أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
        ),
      );
    }
    if (filteredColorListForSeries.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لم يتم العثور على ألوان. يرجى إضافة ألوان من قائمة المنتجات أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: 'Select Series',
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              filled: true,
              fillColor: Colors.white,
            ),
            initialValue: selectedSeriesId,
            items: seriesList.map((s) {
              String displayName = s['name'].toString();
              if (s['profile_name'] != null) {
                displayName = "${s['profile_name']} - $displayName";
              }
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(displayName, style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold)),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedSeriesId = val;
              });
              _updateFilteredColors();
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: filteredColorListForSeries.length,
            itemBuilder: (context, index) {
              final color = filteredColorListForSeries[index];
              final cId = color['id'] as int;
              double currentPrice = 0.0;
              if (selectedSeriesId != null &&
                  seriesColorPrices.containsKey(selectedSeriesId)) {
                currentPrice = seriesColorPrices[selectedSeriesId]?[cId] ?? 0.0;
              }

              TextEditingController ctrl = TextEditingController(
                text: currentPrice.toString(),
              );

              return Container(
                margin: EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  border: Border.all(width: 1, color: Colors.grey.shade300),
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withValues(alpha: 0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 20,
                    vertical: 8,
                  ),
                  title: Text(
                    color['name'].toString(),
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  subtitle: Text(
                    Localization.translate('سعر المتر الطولي', lang),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: ctrl,
                          readOnly: !canChangePrices,
                          keyboardType: TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(10),
                            ),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            suffixText: 'DZD',
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      if (canChangePrices)
                        Container(
                          decoration: BoxDecoration(
                            color: Colors.blue.withValues(alpha: 0.1),
                            shape: BoxShape.circle,
                          ),
                          child: IconButton(
                            icon: Icon(Icons.save, color: Colors.blue),
                            onPressed: () {
                              double? parsed = double.tryParse(ctrl.text);
                              if (parsed != null && selectedSeriesId != null) {
                                _updateSeriesColorPrice(
                                  selectedSeriesId!,
                                  cId,
                                  parsed,
                                );
                              }
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }


  Future<void> _updateAccessoryColorPrice(int accId, int colorId, double price) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    await db.setAccessoryColorPrice(accId, colorId, price);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Widget _buildAccessoryColorTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (accessoryList.isEmpty) {
      return Center(child: Text(Localization.translate('لم يتم العثور على أكسسوارات.', lang)));
    }
    if (allColorList.isEmpty) {
      return Center(child: Text(Localization.translate('لم يتم العثور على ألوان.', lang)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: Localization.translate('اختر الأكسسوار', lang),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              filled: true,
              fillColor: Colors.white,
            ),
            initialValue: selectedAccessoryId,
            items: accessoryList.map((a) {
              return DropdownMenuItem<int>(
                value: a['id'] as int,
                child: Text(a['name'].toString()),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedAccessoryId = val;
              });
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: allColorList.length,
            itemBuilder: (context, index) {
              final color = allColorList[index];
              final cId = color['id'] as int;
              double currentPrice = 0.0;
              if (selectedAccessoryId != null && accessoryColorPrices.containsKey(selectedAccessoryId)) {
                currentPrice = accessoryColorPrices[selectedAccessoryId]?[cId] ?? 0.0;
              }

              TextEditingController ctrl = TextEditingController(text: currentPrice.toString());

              return Container(
                margin: EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  border: Border.all(width: 1, color: Colors.grey.shade300),
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: ListTile(
                  title: Text(color['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold)),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: ctrl,
                          readOnly: !canChangePrices,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            suffixText: 'DZD',
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      if (canChangePrices)
                        IconButton(
                          icon: Icon(Icons.save, color: Colors.blue),
                          onPressed: () {
                            double? parsed = double.tryParse(ctrl.text);
                            if (parsed != null && selectedAccessoryId != null) {
                              _updateAccessoryColorPrice(selectedAccessoryId!, cId, parsed);
                            }
                          },
                        ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _updateSectionColorPrice(int sectionId, int colorId, double price) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    await db.setSectionColorPrice(sectionId, colorId, price);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(Localization.translate('تم تحديث السعر بنجاح', lang)),
          backgroundColor: Colors.green,
        ),
      );
    }
    _loadAllData();
  }

  Future<void> _toggleProfileColor(int profileId, int colorId, bool isSelected) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final dbInstance = (await db.db)!;
    if (isSelected) {
      await dbInstance.insert('ProfileColors', {'profile_id': profileId, 'color_id': colorId});
    } else {
      await dbInstance.delete('ProfileColors', where: 'profile_id = ? AND color_id = ?', whereArgs: [profileId, colorId]);
    }
    _loadAllData();
  }

  Widget _buildProfileColorsTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (profilesList.isEmpty) {
      return Center(child: Text(Localization.translate('لا يوجد أنظمة (Profiles).', lang)));
    }
    if (allColorList.isEmpty) {
      return Center(child: Text(Localization.translate('لا توجد ألوان.', lang)));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: Localization.translate('اختر النظام (Profile)', lang),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              filled: true,
              fillColor: Colors.white,
            ),
            initialValue: selectedProfileId,
            items: profilesList.map((p) {
              return DropdownMenuItem<int>(
                value: p['id'] as int,
                child: Text(p['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold)),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedProfileId = val;
              });
            },
          ),
        ),
        Expanded(
          child: Builder(
            builder: (context) {
              if (selectedProfileId == null) {
                return Center(child: Text(Localization.translate('الرجاء اختيار نظام لرؤية ألوانه.', lang), style: TextStyle(color: Colors.grey, fontSize: 16)));
              }
              
              final profileColors = allColorList.where((color) {
                final cId = color['id'] as int;
                String type = color['type'].toString();
                if (type == 'عام (Global)' || type == 'Global') return true;
                if (profileColorsMap.containsKey(selectedProfileId)) {
                  return profileColorsMap[selectedProfileId]!.contains(cId);
                }
                return false;
              }).toList();

              if (profileColors.isEmpty) {
                return Center(child: Text(Localization.translate('لا توجد ألوان مرتبطة بهذا النظام.', lang)));
              }

              return ListView.builder(
                padding: EdgeInsets.all(16),
                itemCount: profileColors.length,
                itemBuilder: (context, index) {
                  final color = profileColors[index];
                  
                  return Card(
                    elevation: 3,
                    margin: EdgeInsets.only(bottom: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                      title: Text(
                        color['name'].toString(),
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.blue.shade800),
                      ),
                      trailing: Icon(Icons.palette, color: Colors.grey.shade400),
                    ),
                  );
                },
              );
            }
          ),
        ),
      ],
    );
  }

  Widget _buildSectionPricingTab(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (seriesList.isEmpty) {
      return Center(child: Text(Localization.translate('لا توجد سلاسل.', lang)));
    }

    final filteredSections = sectionList.where((s) => s['series_id'] == selectedSeriesForSections).toList();
    
    // Find profile_id for selected series to know which colors to show
    int? currentProfileId;
    if (selectedSeriesForSections != null) {
      final s = seriesList.firstWhere((s) => s['id'] == selectedSeriesForSections, orElse: () => {});
      if (s.isNotEmpty) currentProfileId = s['profile_id'] as int?;
    }
    
    List<int> availableColors = [];
    if (currentProfileId != null && profileColorsMap.containsKey(currentProfileId)) {
      availableColors = profileColorsMap[currentProfileId]!;
    }
    
    final validColors = allColorList.where((c) => availableColors.contains(c['id'] as int)).toList();

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: Localization.translate('اختر السلسلة', lang),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              filled: true,
              fillColor: Colors.white,
            ),
            initialValue: selectedSeriesForSections,
            items: seriesList.map((s) {
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(s['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold)),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedSeriesForSections = val;
              });
            },
          ),
        ),
        if (validColors.isEmpty && selectedSeriesForSections != null)
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(Localization.translate("يرجى تحديد ألوان النظام أولاً من تبويب 'ألوان الأنظمة'.", lang), style: TextStyle(color: Colors.red)),
          ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: filteredSections.length,
            itemBuilder: (context, index) {
              final section = filteredSections[index];
              final secId = section['id'] as int;

              return Card(
                margin: EdgeInsets.only(bottom: 15),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
                elevation: 2,
                child: Padding(
                  padding: EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(section['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18, color: Colors.blue)),
                      Text("${Localization.translate('الرمز', lang)}: ${section['code']}"),
                      SizedBox(height: 10),
                      if (validColors.isNotEmpty)
                        ...validColors.map((color) {
                          final cId = color['id'] as int;
                          double currentPrice = 0.0;
                          if (sectionColorPrices.containsKey(secId)) {
                            currentPrice = sectionColorPrices[secId]?[cId] ?? 0.0;
                          }
                          TextEditingController ctrl = TextEditingController(text: currentPrice.toString());
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8.0),
                            child: Row(
                              children: [
                                Expanded(child: Text(color['name'].toString(), style: TextStyle(fontWeight: FontWeight.w600))),
                                SizedBox(
                                  width: 100,
                                  child: TextField(
                                    controller: ctrl,
                                    readOnly: !canChangePrices,
                                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                                    decoration: InputDecoration(
                                      isDense: true,
                                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                                      suffixText: 'DZD',
                                    ),
                                  ),
                                ),
                                if (canChangePrices)
                                  IconButton(
                                    icon: Icon(Icons.save, color: Colors.blue, size: 20),
                                    onPressed: () {
                                      double? parsed = double.tryParse(ctrl.text);
                                      if (parsed != null) {
                                        _updateSectionColorPrice(secId, cId, parsed);
                                      }
                                    },
                                  )
                              ],
                            ),
                          );
                        }),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildList(

    BuildContext context,
    List<Map<String, dynamic>> list,
    String tableName,
    String nameCol,
    String priceCol,
    String subtitle,
  ) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    if (list.isEmpty) {
      return Center(
        child: Text(
          Localization.translate(
            'لا توجد عناصر. يرجى إضافتها من قائمة المنتجات أولاً.',
            lang,
          ),
          style: TextStyle(fontSize: 18, color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
      );
    }

    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final currentPrice = (item[priceCol] is num)
            ? (item[priceCol] as num).toDouble()
            : 0.0;
        TextEditingController ctrl = TextEditingController(
          text: currentPrice.toString(),
        );
        return Container(
          margin: EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: Colors.grey.shade300),
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(
              item[nameCol].toString(),
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: ctrl,
                    readOnly: !canChangePrices,
                    keyboardType: TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                      suffixText: 'DZD',
                    ),
                  ),
                ),
                SizedBox(width: 10),
                if (canChangePrices)
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.blue.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: IconButton(
                      icon: Icon(Icons.save, color: Colors.blue),
                      onPressed: () {
                        double? parsed = double.tryParse(ctrl.text);
                        if (parsed != null) {
                          _updatePrice(tableName, item['id'], priceCol, parsed);
                        }
                      },
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    AppLanguage lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        title: Text(Localization.translate('إدارة الأسعار', lang)),
        centerTitle: true,
        backgroundColor: Colors.blue,
        elevation: 0,
        bottom: TabBar(
          controller: _tabController,
          isScrollable: true,
          labelColor: Colors.white,
          unselectedLabelColor: Colors.white70,
          indicatorColor: Colors.white,
          tabs: [
            Tab(text: Localization.translate("الألمنيوم (السلاسل)", lang)),
            Tab(text: Localization.translate("ألوان الأنظمة", lang)),
            Tab(text: Localization.translate("الزجاج", lang)),
            Tab(text: Localization.translate("الستائر", lang)),
            Tab(text: Localization.translate("الجوانات", lang)),
            Tab(text: Localization.translate("الإكسسوارات", lang)),
            Tab(text: Localization.translate("أسعار المقاطع", lang)),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSeriesColorTab(context),
                _buildProfileColorsTab(context),
                _buildList(
                  context,
                  glassList,
                  'Glass',
                  'name',
                  'price_per_sqm',
                  Localization.translate('سعر المتر المربع', lang),
                ),
                _buildList(
                  context,
                  shutterList,
                  'ShutterComponents',
                  'name',
                  'price',
                  Localization.translate('سعر المتر المربع', lang),
                ),
                _buildList(
                  context,
                  jointList,
                  'Joints',
                  'name',
                  'price_per_meter',
                  Localization.translate('سعر المتر الطولي', lang),
                ),
                _buildAccessoryColorTab(context),
                _buildSectionPricingTab(context),
              ],
            ),
    );
  }
}
