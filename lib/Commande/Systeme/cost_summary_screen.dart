import 'package:flutter/material.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';
import '../../sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';

class CostSummaryScreen extends StatefulWidget {
  final WindowModel model;

  const CostSummaryScreen({super.key, required this.model});

  @override
  State<CostSummaryScreen> createState() => _CostSummaryScreenState();
}

class _CostSummaryScreenState extends State<CostSummaryScreen> {
  final db = SqlDatabase();

  List<Map<String, dynamic>> seriesList = [];
  List<Map<String, dynamic>> glassList = [];
  List<Map<String, dynamic>> shutterList = [];
  List<Map<String, dynamic>> jointList = [];
  List<Map<String, dynamic>> accessoryList = [];
  List<Map<String, dynamic>> colorList = [];
  Map<int, Map<int, double>> seriesColorPrices = {};

  Map<String, dynamic>? selectedSeries;
  Map<String, dynamic>? selectedGlass;
  Map<String, dynamic>? selectedShutter;
  Map<String, dynamic>? selectedJoint;
  Map<String, dynamic>? selectedAccessory;
  Map<String, dynamic>? selectedColor;

  double totalCost = 0.0;
  double sellingPrice = 0.0;
  bool isLoading = true;

  // Dimensions calculated from WindowModel
  double frameLength = 0;
  double sashLength = 0;
  double totalAlumLength = 0;
  double glassArea = 0;
  double shutterArea = 0;
  double jointPerimeter = 0;

  // Options
  bool hasSystemOB = false;
  bool hasVerrouCentral = false;

  // Exact Counts from Drawing
  int exactHingesCount = 0;
  int exactHandlesCount = 0;
  int exactRollersCount = 0;
  int exactSashesCount = 0;
  int exactTasseauCount = 0;
  int exactReinforcementScrews = 0;
  int exactAccessoryScrews = 0;
  int exactShutterScrews = 0;

  @override
  void initState() {
    super.initState();
    _loadData();
    _calculateDimensions();
  }

  void _calculateDimensions() {
    double w = widget.model.width / 1000;
    double h = widget.model.height / 1000;

    frameLength = (h * 2) + (widget.model.hasBottomFrame ? w * 2 : w);

    int sashes = 0;
    int hinges = 0;
    int handles = 0;
    int rollers = 0;

    double tempSashLength = 0;
    double tempGlassArea = 0;
    double tempJointPerimeter = 0;

    for (var z in widget.model.zones) {
      double zw = z.boundary.width / 1000;
      double zh = z.boundary.height / 1000;
      
      if (z.content == ZoneContent.empty) continue;
      
      // Calculate glass area roughly for the zone
      double zoneGlassArea = (zw - 0.12) * (zh - 0.12);
      if (zoneGlassArea > 0) tempGlassArea += zoneGlassArea;

      if (z.content == ZoneContent.singleSash) {
        sashes += 1;
        hinges += (zh > 1.5) ? 3 : 2; // 3 hinges if height > 1.5m
        handles += 1;
        tempSashLength += (zw * 2) + (zh * 2);
        tempJointPerimeter += (zw * 2) + (zh * 2);
      } else if (z.content == ZoneContent.doubleSash) {
        sashes += 2;
        hinges += (zh > 1.5) ? 6 : 4;
        handles += 1; 
        tempSashLength += (zw * 2) + (zh * 4); 
        tempJointPerimeter += (zw * 2) + (zh * 4);
      } else if (z.content == ZoneContent.slidingSash) {
        int count = z.slidingSashesCount > 0 ? z.slidingSashesCount : 2;
        sashes += count;
        handles += count;
        rollers += count * 2; // 2 rollers per sliding sash
        tempSashLength += (zw * 2) + (zh * count * 2); 
        tempJointPerimeter += (zw * 2) + (zh * count * 2);
      } else if (z.content == ZoneContent.fixedGlass) {
        tempJointPerimeter += (zw * 2) + (zh * 2);
      }
    }

    sashLength = tempSashLength;
    glassArea = tempGlassArea;
    jointPerimeter = tempJointPerimeter + frameLength; 
    totalAlumLength = frameLength + sashLength;
    shutterArea = widget.model.hasShutter ? (w * h) : 0;

    setState(() {
      exactSashesCount = sashes;
      exactHingesCount = hinges;
      exactHandlesCount = handles;
      exactRollersCount = rollers;
    });
  }




  Future<void> _loadData() async {
    final dbInstance = (await db.db)!;
    
    Future<List<Map<String, dynamic>>> safeQuery(String table) async {
      try {
        return await dbInstance.query(table);
      } catch (e) {
        print("Error loading $table: $e");
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
             await dbInstance.execute('ALTER TABLE Colors ADD COLUMN price REAL NOT NULL DEFAULT 0.0;');
          } catch(e){}
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
             await dbInstance.execute('ALTER TABLE Series ADD COLUMN price_per_meter REAL NOT NULL DEFAULT 0.0;');
          } catch(e){}
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

    final sList = await safeQuery('Series');
    final gList = await safeQuery('Glass');
    final shList = await safeQuery('Shutters');
    final jList = await safeQuery('Joints');
    final aList = await safeQuery('Accessories');
    final cList = await safeQuery('Colors');

    Map<int, Map<int, double>> tempPrices = {};
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

    if (!mounted) return;
    setState(() {
      seriesList = sList;
      glassList = gList;
      shutterList = shList;
      jointList = jList;
      accessoryList = aList;
      colorList = cList;
      seriesColorPrices = tempPrices;

      if (seriesList.isNotEmpty) selectedSeries = seriesList.first;
      if (glassList.isNotEmpty) selectedGlass = glassList.first;
      if (shutterList.isNotEmpty && widget.model.hasShutter) {
        selectedShutter = shutterList.first;
      }
      if (jointList.isNotEmpty) selectedJoint = jointList.first;
      if (accessoryList.isNotEmpty) selectedAccessory = accessoryList.first;
      if (colorList.isNotEmpty) {
        if (widget.model.selectedDbColor != null) {
          int id = widget.model.selectedDbColor!['id'];
          selectedColor = colorList.firstWhere((c) => c['id'] == id, orElse: () => colorList.first);
        } else {
          selectedColor = colorList.first;
        }
      }

      isLoading = false;
      _calculateCost();
    });
  }




  
  double _parsePrice(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0;
  }

  void _calculateCost() {
    double cost = 0.0;

    // 1. Aluminum Cost (by linear meter using SeriesColorPrices)
    if (selectedSeries != null) {
      double priceMeter = 0.0;
      if (selectedColor != null && seriesColorPrices.containsKey(selectedSeries!['id'])) {
        priceMeter = seriesColorPrices[selectedSeries!['id']]?[selectedColor!['id']] ?? 0.0;
      }
      // Fallback to series default if no specific color price
      if (priceMeter == 0.0) {
        priceMeter = _parsePrice(selectedSeries!['price_per_meter']);
      }
      cost += totalAlumLength * priceMeter;
    }

    // 2. Glass Cost
    if (selectedGlass != null) {
      double pSq = _parsePrice(selectedGlass!['price_per_sqm']);
      cost += glassArea * pSq;
    }

    // 3. Shutter Cost
    if (widget.model.hasShutter && selectedShutter != null) {
      double pSq = _parsePrice(selectedShutter!['price_per_sqm']);
      cost += shutterArea * pSq;
    }

    // 4. Joint Cost
    if (selectedJoint != null) {
      double pM = _parsePrice(selectedJoint!['price_per_meter']);
      cost += jointPerimeter * pM;
    }

    // 5. Accessory Cost (Calculated exactly from drawing)
    double accessoriesCost = 0.0;
    double handlePrice = _getPriceByType('مقبض');
    double hingePrice = _getPriceByType('مفاصل');
    double rollerPrice = _getPriceByType('عجلات');
    double tasseauPrice = _getPriceByType('الطاسو');
    double screwsPrice = _getPriceByType('البراغي');
    double obPrice = _getPriceByType('سيستم أو بي');
    double verrouPrice = _getPriceByType('فيرو سنترال');

    // Advanced Calculations
    bool hasMullion = widget.model.mullionProfiles.isNotEmpty || widget.model.zones.length > 1;
    bool is103 = !widget.model.isFrame140;
    bool is140 = widget.model.isFrame140;
    
    int tCount = 0;
    double couvreJointPerimeter = 0;
    
    if (is140 && widget.model.hasSideCovers) {
      tCount = 0; // نلغي الطاسو
      double w = widget.model.width / 1000;
      double h = widget.model.height / 1000;
      
      double visibleWidth = 0.04; // افتراضي 40 ملم
      if (widget.model.activeSeries != null) {
        final frames = widget.model.activeSeries!.sections.where((s) => s.type == 'frame').toList();
        if (frames.isNotEmpty) {
          final targetFrame = frames.firstWhere(
              (s) => s.name.contains('140') || s.code.contains('140'),
              orElse: () => frames.first);
          if (targetFrame.couvreJointWidth > 0) {
            visibleWidth = targetFrame.couvreJointWidth / 1000;
          }
        }
      }
      
      // طول الكوفرجوا الذي نحتاجه هو طول النافذة زائد الحجم الظاهر مرتين
      double horiz = w + (visibleWidth * 2);
      double vert = h + (visibleWidth * 2);
      couvreJointPerimeter = (horiz * 2) + (vert * 2);
    } else {
      if (hasMullion) {
        tCount += widget.model.mullionProfiles.isNotEmpty ? widget.model.mullionProfiles.length * 2 : 2;
      }
      if (is103 && widget.model.hasShutter) {
        tCount += 2;
      }
    }
    
    exactTasseauCount = tCount;

    exactReinforcementScrews = (totalAlumLength / 0.4).ceil(); // 1 screw per 40cm
    exactAccessoryScrews = (exactHingesCount * 4) + (exactHandlesCount * 2);
    exactShutterScrews = widget.model.hasShutter ? 10 : 0; // standard 10 screws for shutter
    int totalScrews = exactReinforcementScrews + exactAccessoryScrews + exactShutterScrews;

    accessoriesCost += (exactHandlesCount * handlePrice);
    accessoriesCost += (exactHingesCount * hingePrice);
    accessoriesCost += (exactRollersCount * rollerPrice);
    accessoriesCost += (exactTasseauCount * tasseauPrice);
    
    double couvreJointCost = 0;
    if (couvreJointPerimeter > 0) {
      double cjPrice = _getPriceByType('كوفرجوا'); // أو غطاء جانبي
      if (cjPrice == 0) cjPrice = _getPriceByType('غطاء جانبي');
      couvreJointCost = couvreJointPerimeter * cjPrice;
    }

    accessoriesCost += (totalScrews * screwsPrice) + couvreJointCost;

    if (hasSystemOB) accessoriesCost += obPrice;
    if (hasVerrouCentral) accessoriesCost += verrouPrice;

    cost += accessoriesCost;

    // 6. Color Cost
    if (selectedColor != null) {
      double pColor = _parsePrice(selectedColor!['price']);
      cost += pColor;
    }

    // Calculate Selling Price based on Settings
    double finalPrice = 0.0;
    try {
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      double margin = settings.profitMargin;
      
      if (settings.costMethod == CostMethod.percentage) {
        finalPrice = cost + (cost * (margin / 100.0));
      } else if (settings.costMethod == CostMethod.linearMeter) {
        double perimeter = (widget.model.width / 1000) * 2 + (widget.model.height / 1000) * 2;
        double basePrice = selectedSeries != null ? _parsePrice(selectedSeries!['price_per_meter']) : 0.0;
        finalPrice = (perimeter * basePrice) + accessoriesCost + (selectedGlass != null ? glassArea * _parsePrice(selectedGlass!['price_per_sqm']) : 0.0);
      } else if (settings.costMethod == CostMethod.squareMeter) {
        double area = (widget.model.width / 1000) * (widget.model.height / 1000);
        double basePriceSq = selectedSeries != null ? _parsePrice(selectedSeries!['price_per_meter']) : 0.0; // Using the same field temporarily
        finalPrice = (area * basePriceSq) + accessoriesCost + (selectedGlass != null ? glassArea * _parsePrice(selectedGlass!['price_per_sqm']) : 0.0);
      }
    } catch (e) {
      finalPrice = cost; // fallback
    }

    setState(() {
      totalCost = cost;
      sellingPrice = finalPrice;
    });
  }
  double _getPriceByType(String category) {
    String quality = '';
    if (selectedAccessory != null && selectedAccessory!['type'].toString().contains('|')) {
       quality = selectedAccessory!['type'].toString().split('|')[1];
    }
    
    var matches = accessoryList.where((a) {
      String t = a['type'].toString();
      if (quality.isNotEmpty) {
        return t.contains(category) && t.contains(quality);
      }
      return t.contains(category);
    }).toList();
    
    if (matches.isNotEmpty) {
      return _parsePrice(matches.first['price']);
    }
    return 0.0; 
  }

  @override
  Widget build(BuildContext context) {
    if (isLoading) {
      return Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    AppLanguage lang = Provider.of<AppSettingsProvider>(context).language;

    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate("حساب التكلفة", lang)),
        backgroundColor: Colors.blueAccent,
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.0),
        child: Column(
          children: [
            // Dimension and Accessory Details Header
            Card(
              elevation: 4,
              child: Padding(
                padding: EdgeInsets.all(12),
                child: Column(
                  children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoStat(
                          Localization.translate("العرض", lang),
                          "${widget.model.width.toInt()} mm",
                        ),
                        _infoStat(
                          Localization.translate("الارتفاع", lang),
                          "${widget.model.height.toInt()} mm",
                        ),
                        _infoStat(
                          Localization.translate("الظلفات", lang),
                          "$exactSashesCount",
                        ),
                      ],
                    ),
                    Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoStat(
                          Localization.translate("المفاصل", lang),
                          "$exactHingesCount",
                        ),
                        _infoStat(
                          Localization.translate("المقابض", lang),
                          "$exactHandlesCount",
                        ),
                        _infoStat(
                          Localization.translate("العجلات", lang),
                          "$exactRollersCount",
                        ),
                      ],
                    ),
                    Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceAround,
                      children: [
                        _infoStat(
                          Localization.translate("الطاسو", lang),
                          "$exactTasseauCount",
                        ),
                        _infoStat(
                          Localization.translate("براغي الإكسسوار", lang),
                          "$exactAccessoryScrews",
                        ),
                        _infoStat(
                          Localization.translate("براغي الدعم", lang),
                          "$exactReinforcementScrews",
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            SizedBox(height: 20),

            // Dropdowns for Selections
            _buildDropdown(
              label: Localization.translate("السلسلة (Series)", lang),
              value: selectedSeries,
              items: seriesList,
              onChanged: (val) {
                setState(() => selectedSeries = val);
                _calculateCost();
              },
            ),
            _buildDropdown(
              label: Localization.translate("الزجاج (Glass)", lang),
              value: selectedGlass,
              items: glassList,
              onChanged: (val) {
                setState(() => selectedGlass = val);
                _calculateCost();
              },
            ),
            if (widget.model.hasShutter)
              _buildDropdown(
                label: Localization.translate("الستائر (Shutters)", lang),
                value: selectedShutter,
                items: shutterList,
                onChanged: (val) {
                  setState(() => selectedShutter = val);
                  _calculateCost();
                },
              ),
            _buildDropdown(
              label: Localization.translate("الجلدات (Joints)", lang),
              value: selectedJoint,
              items: jointList,
              onChanged: (val) {
                setState(() => selectedJoint = val);
                _calculateCost();
              },
            ),
            _buildDropdown(
              label: Localization.translate("الإكسسوارات (Accessories)", lang),
              value: selectedAccessory,
              items: accessoryList,
              onChanged: (val) {
                setState(() => selectedAccessory = val);
                _calculateCost();
              },
            ),
            _buildDropdown(
              label: Localization.translate("اللون (Color)", lang),
              value: selectedColor,
              items: colorList,
              onChanged: (val) {
                setState(() => selectedColor = val);
                _calculateCost();
              },
            ),
            
            // Optional Accessories
            Card(
              margin: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
              elevation: 2,
              child: Column(
                children: [
                  CheckboxListTile(
                    title: Text("سيستم أو بي (System OB)", style: TextStyle(fontWeight: FontWeight.bold)),
                    value: hasSystemOB,
                    onChanged: (val) {
                      setState(() => hasSystemOB = val ?? false);
                      _calculateCost();
                    },
                    activeColor: Colors.blue.shade700,
                  ),
                  CheckboxListTile(
                    title: Text("فيرو سنترال (Verrou Central)", style: TextStyle(fontWeight: FontWeight.bold)),
                    value: hasVerrouCentral,
                    onChanged: (val) {
                      setState(() => hasVerrouCentral = val ?? false);
                      _calculateCost();
                    },
                    activeColor: Colors.blue.shade700,
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),

            // Result Display
            Container(
              padding: EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.green.shade50,
                borderRadius: BorderRadius.circular(15),
                border: Border.all(color: Colors.green.shade300, width: 2),
              ),
              child: Column(
                children: [
                  Text(
                    Localization.translate("تكلفة المواد", lang),
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.green.shade700,
                    ),
                  ),
                  SizedBox(height: 5),
                  Text(
                    "${totalCost.toStringAsFixed(2)} DZD",
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Colors.green.shade800,
                    ),
                  ),
                  Divider(color: Colors.green.shade200, height: 30, thickness: 1),
                  Text(
                    Localization.translate("سعر البيع النهائي", lang) + " (${Provider.of<AppSettingsProvider>(context).costMethod == CostMethod.percentage ? 'نسبة مئوية' : Provider.of<AppSettingsProvider>(context).costMethod == CostMethod.linearMeter ? 'متر طولي' : 'متر مربع'})",
                    style: TextStyle(
                      fontSize: 18,
                      color: Colors.blue.shade800,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  SizedBox(height: 10),
                  Text(
                    "${sellingPrice.toStringAsFixed(2)} DZD",
                    style: TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      color: Colors.blue.shade900,
                    ),
                  ),
                ],
              ),
            ),
            
            SizedBox(height: 20),
            
            // زر إضافة الطلب
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                minimumSize: Size(double.infinity, 60),
                backgroundColor: Colors.blue.shade700,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              ),
              onPressed: () {
                widget.model.totalCost = sellingPrice;
                // نعود ونمرر النافذة
                Navigator.pop(context, widget.model);
              },
              icon: Icon(Icons.check_circle, color: Colors.white),
              label: Text(
                Localization.translate('إضافة الطلب', lang),
                style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
            SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _infoStat(String title, String value) {
    return Column(
      children: [
        Text(title, style: TextStyle(color: Colors.grey.shade600)),
        Text(
          value,
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
        ),
      ],
    );
  }

  Widget _buildDropdown({
    required String label,
    required Map<String, dynamic>? value,
    required List<Map<String, dynamic>> items,
    required Function(Map<String, dynamic>?) onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8.0),
      child: DropdownButtonFormField<Map<String, dynamic>>(
        decoration: InputDecoration(
          labelText: label,
          border: OutlineInputBorder(),
        ),
        initialValue: value,
        items: items.map((item) {
          return DropdownMenuItem<Map<String, dynamic>>(
            value: item,
            child: Text(item['name'].toString()),
          );
        }).toList(),
        onChanged: onChanged,
      ),
    );
  }
}
