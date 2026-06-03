import re

file_path = "lib/Screen/price_management_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# We will replace the entire file content with the new UI.
new_content = """import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';

class PriceManagementScreen extends StatefulWidget {
  const PriceManagementScreen({super.key});

  @override
  State<PriceManagementScreen> createState() => _PriceManagementScreenState();
}

class _PriceManagementScreenState extends State<PriceManagementScreen> with SingleTickerProviderStateMixin {
  final SqlDatabase db = SqlDatabase();
  late TabController _tabController;

  List<Map<String, dynamic>> seriesList = [];
  List<Map<String, dynamic>> colorList = [];
  List<Map<String, dynamic>> glassList = [];
  List<Map<String, dynamic>> shutterList = [];
  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> jointList = [];

  Map<int, Map<int, double>> seriesColorPrices = {};

  bool isLoading = true;
  int? selectedSeriesId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 6, vsync: this);
    _loadAllData();
  }

  Future<void> _loadAllData() async {
    final dbInstance = (await db.db)!;
    final sList = await dbInstance.query('Series');
    final cList = await dbInstance.query('Colors');
    final gList = await dbInstance.query('Glass');
    final shList = await dbInstance.query('Shutters');
    final aList = await dbInstance.query('Accessories');
    final jList = await dbInstance.query('Joints');

    final pricesData = await dbInstance.query('SeriesColorPrices');
    Map<int, Map<int, double>> tempPrices = {};
    for (var row in pricesData) {
      int sId = row['series_id'] as int;
      int cId = row['color_id'] as int;
      double p = (row['price'] as num).toDouble();
      if (!tempPrices.containsKey(sId)) {
        tempPrices[sId] = {};
      }
      tempPrices[sId]![cId] = p;
    }

    if (!mounted) return;
    setState(() {
      seriesList = sList;
      colorList = cList;
      glassList = gList;
      shutterList = shList;
      accessoryList = aList;
      jointList = jList;
      seriesColorPrices = tempPrices;
      
      if (seriesList.isNotEmpty && selectedSeriesId == null) {
        selectedSeriesId = seriesList.first['id'] as int;
      }
      
      isLoading = false;
    });
  }

  Future<void> _updatePrice(String table, int id, String column, double newPrice) async {
    final dbInstance = (await db.db)!;
    await dbInstance.update(
      table,
      {column: newPrice},
      where: 'id = ?',
      whereArgs: [id],
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Price updated successfully'), backgroundColor: Colors.green),
    );
    _loadAllData();
  }

  Future<void> _updateSeriesColorPrice(int seriesId, int colorId, double price) async {
    await db.setSeriesColorPrice(seriesId, colorId, price);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Price updated successfully'), backgroundColor: Colors.green),
    );
    _loadAllData();
  }

  Widget _buildSeriesColorTab() {
    if (seriesList.isEmpty || colorList.isEmpty) {
      return Center(child: Text('No data found'));
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: DropdownButtonFormField<int>(
            decoration: InputDecoration(
              labelText: 'Select Series',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(15)),
              filled: true,
              fillColor: Colors.white,
            ),
            value: selectedSeriesId,
            items: seriesList.map((s) {
              return DropdownMenuItem<int>(
                value: s['id'] as int,
                child: Text(s['name'].toString()),
              );
            }).toList(),
            onChanged: (val) {
              setState(() {
                selectedSeriesId = val;
              });
            },
          ),
        ),
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.all(16),
            itemCount: colorList.length,
            itemBuilder: (context, index) {
              final color = colorList[index];
              final cId = color['id'] as int;
              double currentPrice = 0.0;
              if (selectedSeriesId != null && seriesColorPrices.containsKey(selectedSeriesId)) {
                currentPrice = seriesColorPrices[selectedSeriesId]?[cId] ?? 0.0;
              }
              
              TextEditingController ctrl = TextEditingController(text: currentPrice.toString());
              
              return Container(
                margin: EdgeInsets.only(bottom: 15),
                decoration: BoxDecoration(
                  border: Border.all(width: 1, color: Colors.grey.shade300),
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.grey.withOpacity(0.1),
                      spreadRadius: 2,
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ListTile(
                  contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
                  title: Text(color['name'].toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                  subtitle: Text('Price per linear meter'),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        width: 100,
                        child: TextField(
                          controller: ctrl,
                          keyboardType: TextInputType.numberWithOptions(decimal: true),
                          decoration: InputDecoration(
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                            contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                            suffixText: 'DZD',
                          ),
                        ),
                      ),
                      SizedBox(width: 10),
                      Container(
                        decoration: BoxDecoration(
                          color: Colors.blue.withOpacity(0.1),
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(Icons.save, color: Colors.blue),
                          onPressed: () {
                            double? parsed = double.tryParse(ctrl.text);
                            if (parsed != null && selectedSeriesId != null) {
                              _updateSeriesColorPrice(selectedSeriesId!, cId, parsed);
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

  Widget _buildList(List<Map<String, dynamic>> list, String tableName, String nameCol, String priceCol, String subtitle) {
    if (list.isEmpty) {
      return Center(child: Text('No data found'));
    }
    return ListView.builder(
      padding: EdgeInsets.all(16),
      itemCount: list.length,
      itemBuilder: (context, index) {
        final item = list[index];
        final currentPrice = (item[priceCol] is num) ? (item[priceCol] as num).toDouble() : 0.0;
        TextEditingController ctrl = TextEditingController(text: currentPrice.toString());
        return Container(
          margin: EdgeInsets.only(bottom: 15),
          decoration: BoxDecoration(
            border: Border.all(width: 1, color: Colors.grey.shade300),
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withOpacity(0.1),
                spreadRadius: 2,
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: ListTile(
            contentPadding: EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            title: Text(item[nameCol].toString(), style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
            subtitle: Text(subtitle),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 100,
                  child: TextField(
                    controller: ctrl,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                      suffixText: 'DZD',
                    ),
                  ),
                ),
                SizedBox(width: 10),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.blue.withOpacity(0.1),
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
        title: Text('Manage Prices'),
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
            Tab(text: "Aluminum (Series)"),
            Tab(text: "Colors"),
            Tab(text: "Glass"),
            Tab(text: "Shutters"),
            Tab(text: "Joints"),
            Tab(text: "Accessories"),
          ],
        ),
      ),
      body: isLoading
          ? Center(child: CircularProgressIndicator())
          : TabBarView(
              controller: _tabController,
              children: [
                _buildSeriesColorTab(),
                _buildList(colorList, 'Colors', 'name', 'price', 'Additional price'),
                _buildList(glassList, 'Glass', 'name', 'price_per_sqm', 'Price per square meter'),
                _buildList(shutterList, 'Shutters', 'name', 'price_per_sqm', 'Price per square meter'),
                _buildList(jointList, 'Joints', 'name', 'price_per_meter', 'Price per linear meter'),
                _buildList(accessoryList, 'Accessories', 'name', 'price', 'Price per piece'),
              ],
            ),
    );
  }
}
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_content)
