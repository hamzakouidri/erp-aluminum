import sys

with open('lib/Screen/price_management_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add sectionList and accessoryColorPrices to State variables
old_vars = '''  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> jointList = [];

  Map<int, Map<int, double>> seriesColorPrices = {};

  bool isLoading = true;'''
new_vars = '''  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> jointList = [];
  List<Map<String, dynamic>> sectionList = [];

  Map<int, Map<int, double>> seriesColorPrices = {};
  Map<int, Map<int, double>> accessoryColorPrices = {};

  bool isLoading = true;
  int? selectedAccessoryId;'''
content = content.replace(old_vars, new_vars)

# 2. Update TabController length
content = content.replace('_tabController = TabController(length: 6, vsync: this);', '_tabController = TabController(length: 7, vsync: this);')

# 3. Load sections and AccessoryColorPrices in _loadAllData
old_queries = '''    final shList = await safeQuery('Shutters');
    final aList = await safeQuery('Accessories');
    final jList = await safeQuery('Joints');

    Map<int, Map<int, double>> tempPrices = {};'''

new_queries = '''    final shList = await safeQuery('Shutters');
    final aList = await safeQuery('Accessories');
    final jList = await safeQuery('Joints');
    final secList = await safeQuery('Sections');

    Map<int, Map<int, double>> tempPrices = {};
    Map<int, Map<int, double>> tempAccPrices = {};'''

content = content.replace(old_queries, new_queries)

old_tempPrices = '''    try {
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
    }'''

new_tempPrices = '''    try {
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
    }'''
content = content.replace(old_tempPrices, new_tempPrices)

old_setState_loadAll = '''      accessoryList = aList;
      jointList = jList;
      seriesColorPrices = tempPrices;

      if (seriesList.isNotEmpty && selectedSeriesId == null) {'''

new_setState_loadAll = '''      accessoryList = aList;
      jointList = jList;
      sectionList = secList;
      seriesColorPrices = tempPrices;
      accessoryColorPrices = tempAccPrices;

      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }
      if (accessoryList.isNotEmpty && selectedAccessoryId == null) {
        selectedAccessoryId = accessoryList.first['id'] as int;
      }'''
content = content.replace(old_setState_loadAll, new_setState_loadAll)

# 4. Fix duplicate series assignment from replace
content = content.replace('''      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }
        selectedSeriesId = seriesList.first['id'] as int;
      }''', '''      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }''')

# 5. Add AccessoryColorPrice updater and tab builder before _buildList
methods_to_insert = '''
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
            value: selectedAccessoryId,
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

  Widget _buildList(
'''
content = content.replace('  Widget _buildList(', methods_to_insert)

# 6. Update Tabs list
old_tabs = '''            Tab(text: Localization.translate("الزجاج", lang)),
            Tab(text: Localization.translate("الستائر", lang)),
            Tab(text: Localization.translate("الجوانات", lang)),
            Tab(text: Localization.translate("الإكسسوارات", lang)),
          ],'''
new_tabs = '''            Tab(text: Localization.translate("الزجاج", lang)),
            Tab(text: Localization.translate("الستائر", lang)),
            Tab(text: Localization.translate("الجوانات", lang)),
            Tab(text: Localization.translate("الإكسسوارات", lang)),
            Tab(text: Localization.translate("Sections Pricing", lang)),
          ],'''
content = content.replace(old_tabs, new_tabs)

# 7. Update TabBarView children
old_tab_views = '''                _buildList(
                  context,
                  accessoryList,
                  'Accessories',
                  'name',
                  'price',
                  Localization.translate('السعر', lang),
                ),
              ],'''
new_tab_views = '''                _buildAccessoryColorTab(context),
                _buildList(
                  context,
                  sectionList,
                  'Sections',
                  'nom',
                  'price',
                  Localization.translate('Section Price', lang),
                ),
              ],'''
content = content.replace(old_tab_views, new_tab_views)


with open('lib/Screen/price_management_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)
