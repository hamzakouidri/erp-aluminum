import 'package:flutter/material.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/cutting_calculator.dart';
import 'package:database_data/sql_database.dart';

class MaterialConsumptionScreen extends StatefulWidget {
  final WindowModel model;

  const MaterialConsumptionScreen({super.key, required this.model});

  @override
  State<MaterialConsumptionScreen> createState() => _MaterialConsumptionScreenState();
}

class _MaterialConsumptionScreenState extends State<MaterialConsumptionScreen> {
  // تخزين الأسعار، المفتاح هو اسم العنصر
  final Map<String, double> _prices = {};
  final SqlDatabase db = SqlDatabase();
  List<MaterialRow> _profiles = [];
  List<MaterialRow> _shutters = [];
  List<MaterialRow> _accessories = [];
  List<MaterialRow> _glass = [];
  List<Map<String, dynamic>> _dbAccessories = [];
  List<Map<String, dynamic>> _dbGlass = [];

  bool _isLoading = true;
  double _defaultShutterPrice = 8000.0;

  @override
  void initState() {
    super.initState();
    _loadDataFromDatabase();
  }

  Future<void> _loadDataFromDatabase() async {
    final items = CuttingCalculator.calculate(widget.model);

    Map<String, double> glassAreas = {};

    for (var item in items) {
      if (item.type == CuttingItemType.glass) {
        double areaSqm = (item.width / 1000.0) * (item.height / 1000.0) * item.quantity;
        String dimStr = '(${item.width.toInt()} x ${item.height.toInt()} mm)';
        String key = '${item.name}__$dimStr';
        glassAreas[key] = (glassAreas[key] ?? 0.0) + areaSqm;
      }
    }

    // --- حساب الألمنيوم المفصل (المتر الخطي) ---
    double hMeters = widget.model.height / 1000.0;
    double wMeters = widget.model.width / 1000.0;
    
    String colorName = 'أبيض';
    double defaultAluPrice = 1200.0;
    _defaultShutterPrice = 8000.0;
    
    switch (widget.model.frameColor) {
      case FrameColor.white:
        colorName = 'أبيض';
        break;
      case FrameColor.brown:
        colorName = 'بني فاتح (Faux Bois)';
        break;
      case FrameColor.gray:
        colorName = 'رمادي';
        break;
      case FrameColor.black:
        colorName = 'أسود';
        break;
      case FrameColor.beige:
        colorName = 'بيج / FBM';
        break;
    }

    Map<String, double> sectionPricesByType = {};
    try {
      final dbInstance = (await db.db)!;
      // Fetch Shutter Price based on color approximation
      String shutterSearch = colorName == 'أبيض' ? 'أبيض' : 'خشبي';
      final shutterRes = await dbInstance.query('ShutterComponents', where: 'name LIKE ?', whereArgs: ['%$shutterSearch%']);
      if (shutterRes.isNotEmpty) {
        _defaultShutterPrice = (shutterRes.first['price'] as num).toDouble();
      }

      // Fetch Aluminum Price
      final colorRes = await dbInstance.query('Colors', where: 'name = ?', whereArgs: [colorName]);
      if (colorRes.isNotEmpty) {
        int colorId = colorRes.first['id'] as int;
        int seriesId = widget.model.activeSeries?.id ?? 0;
        final priceRes = await dbInstance.query('SeriesColorPrices', where: 'series_id = ? AND color_id = ?', whereArgs: [seriesId, colorId]);
        if (priceRes.isNotEmpty) {
          double fetchedPrice = (priceRes.first['price'] as num).toDouble();
          if (fetchedPrice > 0) defaultAluPrice = fetchedPrice;
        }

        // Fetch Section Prices
        if (widget.model.activeSeries != null) {
          for (var sec in widget.model.activeSeries!.sections) {
             final spRes = await dbInstance.query('SectionColorPrices', where: 'section_id = ? AND color_id = ?', whereArgs: [sec.id, colorId]);
             if (spRes.isNotEmpty) {
                double p = (spRes.first['price'] as num).toDouble();
                if (p > 0) sectionPricesByType[sec.type] = p;
             }
          }
        }
      }
    } catch (e) {
      print("Error fetching dynamic prices: $e");
    }

    _profiles = [];
    
    void addProfileCut(String typeName, double cutMeters, int count) {
      if (cutMeters <= 0 || count <= 0) return;
      double barLength = 6.0;
      int cutsPerBar = (barLength / cutMeters).floor();
      if (cutsPerBar < 1) cutsPerBar = 1; // safety for extremely long pieces
      
      String secType = 'frame';
      if (typeName == 'ضلفة') {
        secType = 'sash';
      } else if (typeName == 'باطمو') secType = 'batteuse';
      else if (typeName == 'تقسيم') secType = 'mullion';
      else if (typeName == 'باركلوز') secType = 'parclose';

      double pricePerBar = sectionPricesByType[secType] ?? defaultAluPrice;
      double pricePerCut = pricePerBar / cutsPerBar;
      
      String disp = '$typeName (طول: ${cutMeters.toStringAsFixed(2)} م) - لون: $colorName';
      _prices[disp] = pricePerCut;
      _profiles.add(MaterialRow(name: disp, quantity: count.toDouble(), unit: 'قطعة', typeCategory: 'profile', cutsPerBar: cutsPerBar));
    }

    // الإطار
    addProfileCut('إطار', hMeters, 2);
    if (widget.model.hasBottomFrame) {
      addProfileCut('إطار', wMeters, 2);
    } else {
      addProfileCut('إطار', wMeters, 1);
    }

    // الضلف والزجاج
    for (var zone in widget.model.zones) {
      if (zone.content == ZoneContent.singleSash) {
         addProfileCut('ضلفة', hMeters, 2);
         addProfileCut('ضلفة', wMeters, 2);
         addProfileCut('باركلوز', hMeters, 2);
         addProfileCut('باركلوز', wMeters, 2);
      } else if (zone.content == ZoneContent.doubleSash) {
         addProfileCut('ضلفة', hMeters, 4);
         addProfileCut('ضلفة', wMeters / 2, 4);
         addProfileCut('باركلوز', hMeters, 4);
         addProfileCut('باركلوز', wMeters / 2, 4);
         
         double innerHeight = widget.model.height - (widget.model.hasBottomFrame ? 100.0 : 50.0);
         double sashHeight = innerHeight + 20.0;
         double batteuseMeters = (sashHeight / 1000.0) - 0.06;
         addProfileCut('باطمو', batteuseMeters, 1);
      } else {
         addProfileCut('باركلوز', hMeters, 2);
         addProfileCut('باركلوز', wMeters, 2);
      }
    }
    
    int hMullionCount = widget.model.mullionProfiles.keys.where((k) => k.startsWith('H')).length;
    int vMullionCount = widget.model.mullionProfiles.keys.where((k) => k.startsWith('V')).length;
    addProfileCut('تقسيم', wMeters, hMullionCount);
    addProfileCut('تقسيم', hMeters, vMullionCount);

    // --- حساب السيتار (الستائر) ---
    if (widget.model.hasShutter) {
      double shutterAreaSqm = hMeters * wMeters; // مساحة النافذة كاملة
      
      _shutters = [];
      
      void addShutterComponent(String name, double qty, String unit, double price) {
         if (qty > 0) {
             String disp = '$name - لون: $colorName';
             _prices[disp] = price;
             _shutters.add(MaterialRow(name: disp, quantity: qty, unit: unit));
         }
      }
      
      // الشفرات (Lames) بالحساب الدقيق
      double shutterWidthCm = widget.model.width / 10.0;
      double shutterHeightCm = widget.model.height / 10.0;
      
      double slatCutLengthCm = shutterWidthCm - 6.5; // طول الشفرة المقطوعة
      double slatVisibleHeightCm = 4.3; // ارتفاع الشفرة الظاهر (من قاعدة البيانات مستقبلا)
      double barLengthCm = 580.0; // طول بارة الشفرات كاملة (من قاعدة البيانات مستقبلا)
      
      int numberOfSlats = ((shutterHeightCm - 10.0) / slatVisibleHeightCm).ceil(); // عدد الشفرات للنافذة
      int cutsPerBar = (barLengthCm / slatCutLengthCm).floor(); // كم شفرة نستخرج من البارة الواحدة
      double totalBarsNeeded = cutsPerBar > 0 ? (numberOfSlats / cutsPerBar).ceilToDouble() : 0.0; // عدد البارات الكلي
      
      addShutterComponent('بارات الشفرات (Lames)', totalBarsNeeded, 'بارة (5.8m)', 0.0);
      addShutterComponent('سيتار مجمّع (المساحة)', shutterAreaSqm, 'متر مربع', 0.0); // No inline price, calculate at bottom
      addShutterComponent('كوليس', hMeters * 2, 'متر طولي', 0.0);
      addShutterComponent('كيسون', wMeters, 'متر طولي', 0.0);
      addShutterComponent('أكس', (shutterWidthCm - 7.0) / 100.0, 'متر طولي', 0.0);
      addShutterComponent('لام فينال', (shutterWidthCm - 6.5) / 100.0, 'متر طولي', 0.0);
      addShutterComponent('كيت سيتار', 1.0, 'وحدة', 0.0);
    }

    // --- جلب الزجاج والإكسسوارات من قاعدة البيانات ---
    final dbInstance = await db.db;
    
    // الإكسسوارات
    _dbAccessories = await db.readAccessories();
    int singleCount = widget.model.zones.where((z) => z.content == ZoneContent.singleSash).length;
    int doubleCount = widget.model.zones.where((z) => z.content == ZoneContent.doubleSash).length;
    int totalSashes = singleCount + (doubleCount * 2);
    int totalHandles = singleCount + doubleCount;
    int hingesPerSash = widget.model.height > 1500 ? 3 : 2;
    int totalEquerres = 4 + (4 * totalSashes);
    int totalBouchonBattement = doubleCount > 0 ? doubleCount : 0; // 1 pair per double sash
    
    if (_dbAccessories.isEmpty) {
      _dbAccessories = [
        {'name': 'مقبض (Poignée)', 'type': 'Global', 'price': 250.0},
        {'name': 'مفصلة (Paumelle)', 'type': 'Global', 'price': 150.0},
        {'name': 'زاوية (Equerre)', 'type': 'Global', 'price': 50.0},
        {'name': 'قفل (Serrure/Ferme)', 'type': 'Global', 'price': 400.0},
        {'name': 'كريمون (Crémone)', 'type': 'Global', 'price': 300.0},
        {'name': 'Bouchon battement', 'type': 'Global', 'price': 100.0},
      ];
    }
    
    List<MaterialRow> loadedAccessories = [];
    
    if (totalSashes > 0) {
      bool handleAdded = false;
      bool hingeAdded = false;
      bool equerreAdded = false;
      bool cremoneAdded = false;
      bool lockAdded = false;
      bool bouchonAdded = false;
      
      for (var acc in _dbAccessories) {
        String accName = acc['name'].toString().toLowerCase();
        String accType = acc['type']?.toString().toLowerCase() ?? '';
        double accPrice = double.tryParse(acc['price'].toString()) ?? 0.0;
        int quantity = 0;
        String typeCategory = '';
        
        bool isHandle = accName.contains('مقبض') || accName.contains('poignée') || accType.contains('مقبض');
        bool isHinge = accName.contains('مفصلة') || accName.contains('paumelle') || accType.contains('مفاصل') || accType.contains('paumelle');
        bool isEquerre = accName.contains('زاوية') || accName.contains('equerre') || accType.contains('زاوية');
        bool isCremone = accName.contains('كريمون') || accName.contains('ميكانيزم') || accType.contains('كريمون');
        bool isLock = accName.contains('قفل') || accName.contains('serrure') || accName.contains('فيرو') || accType.contains('فيرو') || accType.contains('إسبانيوليت') || accType.contains('قاش');
        bool isBouchon = accName.contains('bouchon battement') || accName.contains('bouchon');

        // Scope & Material filtering
        String accMaterial = acc['material_type']?.toString() ?? 'Aluminium';
        String accScope = acc['scope']?.toString() ?? 'Global';
        int? accSeriesId = acc['series_id'] as int?;

        String modelMaterial = widget.model.activeSeries?.type ?? 'Aluminium';
        if (modelMaterial == 'Aluminium' && accMaterial != 'Aluminium') continue;
        if (modelMaterial == 'PVC' && accMaterial != 'PVC') continue;
        if (accScope == 'Unique' && accSeriesId != widget.model.activeSeries?.id) continue;

        if (isHandle && !handleAdded) {
          quantity = totalHandles;
          typeCategory = 'handle';
          handleAdded = true;
        } else if (isHinge && !hingeAdded) {
          quantity = hingesPerSash * totalSashes;
          typeCategory = 'hinge';
          hingeAdded = true;
        } else if (isEquerre && !equerreAdded) {
          quantity = totalEquerres;
          typeCategory = 'equerre';
          equerreAdded = true;
        } else if (isCremone && !cremoneAdded) {
          quantity = totalHandles;
          typeCategory = 'cremone';
          cremoneAdded = true;
        } else if (isLock && !lockAdded) {
           quantity = totalHandles;
           typeCategory = 'lock';
           lockAdded = true;
        } else if (isBouchon && totalBouchonBattement > 0 && !bouchonAdded) {
           quantity = totalBouchonBattement;
           typeCategory = 'bouchon';
           bouchonAdded = true;
        } else if (!isHandle && !isHinge && !isEquerre && !isCremone && !isLock && !isBouchon) {
           // Fallback for custom user accessories
           quantity = 1;
           typeCategory = 'other';
        }
        
        if (quantity > 0) {
          _prices[acc['name'].toString()] = accPrice;
          loadedAccessories.add(MaterialRow(
            name: acc['name'].toString(),
            quantity: quantity.toDouble(),
            unit: 'قطعة',
            typeCategory: typeCategory,
          ));
        }
      }
    }

    // الزجاج
    _dbGlass = [];
    if (dbInstance != null) {
      try { _dbGlass = await dbInstance.query('Glass'); } catch (_) {}
    }
    
    List<MaterialRow> loadedGlass = [];
    for (var entry in glassAreas.entries) {
      String glassName = entry.key;
      double area = entry.value;
      
      double price = 0.0;
      var match = _dbGlass.where((g) {
        String dbName = g['name'].toString().toLowerCase().trim();
        // Remove spaces for robust comparison
        String compareName = glassName.toLowerCase().replaceAll(' ', '');
        String compareDb = dbName.replaceAll(' ', '');
        
        if (compareName.contains('مزدوج')) {
          return compareDb.contains('مزدوج') || compareDb.contains('double');
        } else {
          return compareDb.contains('مفرد') || compareDb.contains('simple') || compareDb.contains('single');
        }
      }).toList();

      String displayGlassName = glassName.split('__')[0];
      String dims = glassName.split('__')[1];

      if (match.isNotEmpty) {
        price = double.tryParse(match.first['price_per_sqm'].toString()) ?? 0.0;
        displayGlassName = match.first['name'].toString(); // Full variant name e.g., Stopsol Bleu
      }
      
      String finalRowName = '$displayGlassName $dims';
      _prices[finalRowName] = price;
      
      loadedGlass.add(MaterialRow(
        name: finalRowName,
        quantity: area,
        unit: 'متر مربع',
        typeCategory: 'glass',
      ));
    }

    if (mounted) {
      setState(() {
        // تأكد من عدم مسح _profiles لأننا ملأناها في الأعلى
        _accessories = loadedAccessories;
        _glass = loadedGlass;
        _isLoading = false;
      });
    }
  }

  double get _totalCost {
    double total = 0;
    for (var p in _profiles) {
      total += p.quantity * (_prices[p.name] ?? 0.0);
    }
    for (var s in _shutters) {
      total += s.quantity * (_prices[s.name] ?? 0.0);
    }
    for (var a in _accessories) {
      total += a.quantity * (_prices[a.name] ?? 0.0);
    }
    for (var g in _glass) {
      total += g.quantity * (_prices[g.name] ?? 0.0);
    }
    return total;
  }

  Future<void> _savePriceToDatabase(String itemName, double newPrice) async {
    // This is a best-effort save to database based on item name.
    final dbInstance = await db.db;
    if (dbInstance == null) return;
    
    try {
      // 1. Try to update Glass
      await dbInstance.update(
        'Glass',
        {'price_per_sqm': newPrice},
        where: 'name = ?',
        whereArgs: [itemName]
      );
      
      // 2. Try to update Accessories
      await dbInstance.update(
        'Accessories',
        {'price': newPrice},
        where: 'name = ?',
        whereArgs: [itemName]
      );

      // 3. Try to update Shutters (Volet)
      if (itemName.contains('سيتار') || itemName.contains('Volet')) {
        // Find shutter with exact name or update all for the specific type (complex)
        // Here we can just notify the user
      }
    } catch (e) {
      // Ignore error intentionally or handle it via UI
    }
  }

  void _showChangeAccessoryDialog(MaterialRow item) {
    if (item.typeCategory == null || item.typeCategory!.isEmpty) return;

    List<Map<String, dynamic>> matchingItems = [];
    
    if (item.typeCategory == 'glass') {
      matchingItems = _dbGlass; // All glasses
    } else {
      for (var acc in _dbAccessories) {
        String accName = acc['name'].toString().toLowerCase();
        String accType = acc['type']?.toString().toLowerCase() ?? '';
        
        bool isHandle = accName.contains('مقبض') || accName.contains('poignée') || accType.contains('مقبض');
        bool isHinge = accName.contains('مفصلة') || accName.contains('paumelle') || accType.contains('مفاصل');
        bool isEquerre = accName.contains('زاوية') || accName.contains('equerre') || accType.contains('زاوية');
        bool isCremone = accName.contains('كريمون') || accName.contains('ميكانيزم') || accType.contains('كريمون');
        bool isLock = accName.contains('قفل') || accName.contains('serrure') || accName.contains('فيرو') || accType.contains('فيرو') || accType.contains('إسبانيوليت') || accType.contains('قاش');
        bool isBouchon = accName.contains('bouchon battement') || accName.contains('bouchon');

        if (item.typeCategory == 'handle' && isHandle) {
          matchingItems.add(acc);
        } else if (item.typeCategory == 'hinge' && isHinge) matchingItems.add(acc);
        else if (item.typeCategory == 'equerre' && isEquerre) matchingItems.add(acc);
        else if (item.typeCategory == 'cremone' && isCremone) matchingItems.add(acc);
        else if (item.typeCategory == 'lock' && isLock) matchingItems.add(acc);
        else if (item.typeCategory == 'bouchon' && isBouchon) matchingItems.add(acc);
      }
    }

    if (matchingItems.isEmpty) return;

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('تغيير النوع أو الجودة', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.orange)),
          content: SizedBox(
            width: double.maxFinite,
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: matchingItems.length,
              itemBuilder: (context, index) {
                var itm = matchingItems[index];
                String name = itm['name'].toString();
                double price = item.typeCategory == 'glass' 
                    ? (double.tryParse(itm['price_per_sqm'].toString()) ?? 0.0)
                    : (double.tryParse(itm['price'].toString()) ?? 0.0);
                
                return ListTile(
                  title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                  subtitle: Text('السعر: $price دج', style: const TextStyle(color: Colors.green)),
                  onTap: () {
                    setState(() {
                      if (item.typeCategory == 'glass') {
                        String oldName = item.name;
                        String dims = '';
                        if (oldName.contains('(')) {
                          dims = oldName.substring(oldName.indexOf('('));
                        }
                        String newName = dims.isNotEmpty ? '$name $dims' : name;
                        _prices[newName] = price;
                        item.name = newName;
                      } else {
                        _prices[name] = price;
                        item.name = name;
                      }
                    });
                    Navigator.pop(context);
                  },
                );
              },
            ),
          ),
          actions: [
             TextButton(
               onPressed: () => Navigator.pop(context),
               child: const Text('إلغاء'),
             ),
          ],
        );
      },
    );
  }

  void _showEditDialog(MaterialRow item) {
    double currentPrice = _prices[item.name] ?? 0.0;
    
    double displayPrice = currentPrice;
    if (item.typeCategory == 'profile' && item.cutsPerBar != null && item.cutsPerBar! > 0) {
      displayPrice = currentPrice * item.cutsPerBar!;
    }
    
    TextEditingController ctrl = TextEditingController(
      text: displayPrice > 0 ? displayPrice.toString() : '',
    );
    bool saveToDb = false;

    showDialog(
      context: context,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
              title: Text(item.typeCategory == 'profile' ? 'تعديل سعر البارة (6م)' : 'تحديث السعر', style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueGrey)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(item.name, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                  const SizedBox(height: 15),
                  TextField(
                    controller: ctrl,
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: item.typeCategory == 'profile' ? 'سعر البارة (دج)' : 'السعر الإفرادي (دج)',
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixText: 'دج',
                    ),
                  ),
                  const SizedBox(height: 10),
                  CheckboxListTile(
                    title: const Text("حفظ السعر الجديد في قاعدة البيانات؟", style: TextStyle(fontSize: 13)),
                    value: saveToDb,
                    activeColor: Colors.blue,
                    onChanged: (val) {
                      setDialogState(() {
                        saveToDb = val ?? false;
                      });
                    },
                    controlAffinity: ListTileControlAffinity.leading,
                    contentPadding: EdgeInsets.zero,
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('إلغاء', style: TextStyle(color: Colors.grey)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  ),
                  onPressed: () async {
                    double? parsed = double.tryParse(ctrl.text);
                    if (parsed != null) {
                      setState(() {
                        _prices[item.name] = parsed;
                      });
                      
                      if (saveToDb) {
                        await _savePriceToDatabase(item.name, parsed);
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تحديث السعر وحفظه في قاعدة البيانات بنجاح'),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } else {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text('تم تحديث السعر لهذه النافذة فقط'),
                              backgroundColor: Colors.blue,
                            ),
                          );
                        }
                      }
                      if (context.mounted) Navigator.pop(context);
                    }
                  },
                  child: const Text('تحديث'),
                ),
              ],
            );
          }
        );
      },
    );
  }

  Widget _buildSection(String title, List<MaterialRow> items, Color headerColor) {
    if (items.isEmpty) return const SizedBox();
    
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      color: Colors.white,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: headerColor,
            child: Text(
              title,
              style: const TextStyle(
                fontSize: 16, 
                fontWeight: FontWeight.bold,
                color: Colors.white
              ),
            ),
          ),
          ...items.map((item) {
            double price = _prices[item.name] ?? 0.0;
            double total = price * item.quantity;

            return Column(
              children: [
                ListTile(
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  title: Text(
                    item.name,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                  subtitle: Padding(
                    padding: const EdgeInsets.only(top: 4.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('الكمية: ${item.quantity.toStringAsFixed(2)} ${item.unit}'),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                'السعر الإفرادي: ${price > 0 ? price.toStringAsFixed(2) : '-'} دج',
                                style: TextStyle(color: Colors.grey.shade700, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (total > 0)
                              Text(
                                'المجموع: ${total.toStringAsFixed(2)} دج', 
                                style: const TextStyle(color: Colors.green, fontWeight: FontWeight.bold, fontSize: 14)
                              ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (item.typeCategory != null && item.typeCategory!.isNotEmpty && item.typeCategory != 'profile')
                        IconButton(
                          icon: const Icon(Icons.swap_horiz, color: Colors.orange, size: 24),
                          onPressed: () => _showChangeAccessoryDialog(item),
                          tooltip: 'تغيير النوع',
                        ),
                      if (item.typeCategory != 'profile')
                        IconButton(
                          icon: const Icon(Icons.edit, color: Colors.blue, size: 22),
                          onPressed: () => _showEditDialog(item),
                          tooltip: 'تحديث السعر',
                        ),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),
              ],
            );
          }),
          
          if (items.any((item) => (_prices[item.name] ?? 0.0) > 0) || title == 'الستائر')
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              color: Colors.grey.shade100,
              child: Row(
                children: [
                  const Text('المجموع الفرعي لهذا القسم: ', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  Text(
                    '${title == 'الستائر' ? (widget.model.hasShutter ? _defaultShutterPrice * widget.model.width / 1000.0 * widget.model.height / 1000.0 : 0.0).toStringAsFixed(2) : items.fold(0.0, (sum, item) => sum + ((_prices[item.name] ?? 0.0) * item.quantity)).toStringAsFixed(2)} دج',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16, color: Colors.green),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const Text('الكمية المستهلكة والتكلفة'),
        centerTitle: true,
        backgroundColor: Colors.blueGrey,
        foregroundColor: Colors.white,
      ),
      body: _isLoading 
        ? const Center(child: CircularProgressIndicator())
        : SingleChildScrollView(
            child: Column(
          children: [
            _buildSection('البروفيلات', _profiles, Colors.blueGrey.shade700),
            _buildSection('الستائر', _shutters, Colors.brown.shade600),
            _buildSection('الإكسسوارات', _accessories, Colors.deepOrange.shade600),
            _buildSection('الزجاج', _glass, Colors.teal.shade700),
            const SizedBox(height: 80), // Padding for bottom bar
          ],
        ),
      ),
      bottomSheet: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              offset: const Offset(0, -4),
              blurRadius: 10,
            )
          ]
        ),
        child: SafeArea(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'التكلفة الإجمالية:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.grey),
                  ),
                  Text(
                    '${_totalCost.toStringAsFixed(2)} دج',
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Colors.green,
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue.shade700,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
                onPressed: () {
                  // إرجاع الـ WindowModel مع التكلفة الإجمالية إلى الصفحة الرئيسية
                  widget.model.totalCost = _totalCost;
                  Navigator.pop(context, widget.model);
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text(
                  'إضافة للطلبية',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


class MaterialRow {
  String name;
  final double quantity;
  final String unit;
  final String? typeCategory;
  final int? cutsPerBar;

  MaterialRow({
    required this.name,
    required this.quantity,
    required this.unit,
    this.typeCategory,
    this.cutsPerBar,
  });
}
