import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class AchatItemPicker extends StatefulWidget {
  final int achatId;
  const AchatItemPicker({super.key, required this.achatId});

  @override
  State<AchatItemPicker> createState() => _AchatItemPickerState();
}

class _AchatItemPickerState extends State<AchatItemPicker> {
  final SqlDatabase _db = SqlDatabase();
  final Color _blue = const Color(0xFF1E3A8A);
  final Color _cyan = const Color(0xFF06B6D4);
  
  String _selectedCategory = 'Sections';
  final List<Map<String, String>> _categories = [
    {'id': 'Sections', 'label': 'مقاطع'},
    {'id': 'Accessories', 'label': 'إكسسوارات'},
    {'id': 'Glass', 'label': 'زجاج'},
    {'id': 'Joints', 'label': 'جوانات'},
  ];

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  
  // Filters
  int? _selectedProfileId;
  int? _selectedSeriesId;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _seriesList = [];

  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  Future<void> _loadFilters() async {
    final profiles = await _db.readProfile();
    setState(() {
      _profiles = profiles;
      if (_profiles.isNotEmpty) {
        _selectedProfileId = _profiles.first['id'];
        _loadSeriesForProfile(_selectedProfileId!);
      }
    });
    _loadItems();
  }

  Future<void> _loadSeriesForProfile(int profileId) async {
    final series = await _db.readSeriesByProfile(profileId);
    setState(() {
      _seriesList = series;
      if (_seriesList.isNotEmpty) {
        _selectedSeriesId = _seriesList.first['id'];
      } else {
        _selectedSeriesId = null;
      }
    });
    _loadItems();
  }

  Future<void> _loadItems() async {
    setState(() => _isLoading = true);
    List<Map<String, dynamic>> items = [];
    String query = _searchCtrl.text.trim().toLowerCase();
    
    if (_selectedCategory == 'Sections') {
      if (query.isNotEmpty) {
        // Search globally across all sections
        items = await _db.searchSectionsWithProfile(query);
      } else if (_selectedSeriesId != null) {
        items = await _db.readSectionsBySeries(_selectedSeriesId!);
      }
    } else if (_selectedCategory == 'Accessories') {
      items = await _db.readAccessories();
    } else if (_selectedCategory == 'Glass') {
      items = await _db.readGlass();
    } else if (_selectedCategory == 'Joints') {
      items = await _db.readJoints();
    }

    // Filter locally for non-section categories if there is a search query
    if (query.isNotEmpty && _selectedCategory != 'Sections') {
      items = items.where((item) {
        String name = (item['name'] ?? item['type'] ?? '').toString().toLowerCase();
        String code = (item['code'] ?? '').toString().toLowerCase();
        return name.contains(query) || code.contains(query);
      }).toList();
    }

    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  void _showAddItemDialog(Map<String, dynamic> item) {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController();
    
    // Default price from DB if available
    if (_selectedCategory == 'Accessories') {
      priceCtrl.text = (item['price'] ?? 0.0).toString();
    } else if (_selectedCategory == 'Glass') {
      priceCtrl.text = (item['price_per_sqm'] ?? 0.0).toString();
    } else if (_selectedCategory == 'Joints') {
      priceCtrl.text = (item['price_per_meter'] ?? 0.0).toString();
    }

    int? selectedColorId;
    List<Map<String, dynamic>> colors = [];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) {
          bool colorsLoaded = false;
          if (_selectedCategory == 'Sections' && !colorsLoaded) {
            _db.readColors().then((cList) {
              if (cList.isNotEmpty && mounted) {
                setDialogState(() {
                  colors = cList;
                  selectedColorId = cList.first['id'];
                  colorsLoaded = true;
                });
                // Find old price for this section color
                _db.getSectionColorPrice(item['id'], selectedColorId!).then((p) {
                  if (mounted && p > 0) setDialogState(() => priceCtrl.text = p.toString());
                });
              }
            });
            colorsLoaded = true; // prevent loop
          }

          return AlertDialog(
            title: Text('إضافة ${item['name'] ?? item['type']}', style: TextStyle(fontFamily: 'Cairo')),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (_selectedCategory == 'Sections') ...[
                    DropdownButtonFormField<int>(
                      value: selectedColorId,
                      decoration: InputDecoration(labelText: 'اللون'),
                      items: colors.map((c) => DropdownMenuItem<int>(
                        value: c['id'],
                        child: Text(c['name']),
                      )).toList(),
                      onChanged: (val) {
                        setDialogState(() => selectedColorId = val);
                        if (val != null) {
                          _db.getSectionColorPrice(item['id'], val).then((p) {
                            if (mounted && p > 0) setDialogState(() => priceCtrl.text = p.toString());
                          });
                        }
                      },
                    ),
                    SizedBox(height: 12),
                  ],
                  TextField(
                    controller: qtyCtrl,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: _selectedCategory == 'Sections' ? 'الكمية (عدد الأعمدة)' : 'الكمية',
                      border: OutlineInputBorder(),
                    ),
                  ),
                  SizedBox(height: 12),
                  TextField(
                    controller: priceCtrl,
                    keyboardType: TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: _selectedCategory == 'Sections' ? 'السعر (للعود الواحد)' : 'السعر للوحدة',
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context), child: Text('إلغاء')),
              ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _blue),
                onPressed: () async {
                  double qty = double.tryParse(qtyCtrl.text) ?? 1.0;
                  double price = double.tryParse(priceCtrl.text) ?? 0.0;
                  
                  if (qty > 0 && price >= 0) {
                    await _db.insertAchatItem(
                      achatId: widget.achatId,
                      itemCode: item['code'] ?? item['name'] ?? item['type'] ?? 'Unknown',
                      itemName: item['name'] ?? item['type'] ?? 'Unknown',
                      itemType: _selectedCategory,
                      itemId: item['id'],
                      colorId: selectedColorId,
                      quantity: qty,
                      price: price,
                    );
                    
                    // Update Achat total
                    final achats = await _db.db.then((d) => d!.query('Achats', where: 'id=?', whereArgs: [widget.achatId]));
                    if (achats.isNotEmpty) {
                      double currentTotal = achats.first['total'] as double;
                      double addedValue = qty * price;
                      await _db.db.then((d) => d!.update('Achats', {'total': currentTotal + addedValue}, where: 'id=?', whereArgs: [widget.achatId]));
                    }

                    // Update Catalog Prices if higher!
                    if (_selectedCategory == 'Sections' && selectedColorId != null) {
                      double oldPrice = await _db.getSectionColorPrice(item['id'], selectedColorId!);
                      if (price > oldPrice) {
                        await _db.setSectionColorPrice(item['id'], selectedColorId!, price);
                      }
                    } else if (_selectedCategory == 'Accessories') {
                       double oldPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
                       if (price > oldPrice) {
                          await _db.updateAccessory(item['id'], {'price': price});
                       }
                    }

                    if (context.mounted) {
                      Navigator.pop(context);
                      Navigator.pop(context, true); // return true to refresh
                    }
                  }
                },
                child: Text('إضافة', style: TextStyle(color: Colors.white)),
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text('إضافة عنصر للفاتورة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
        flexibleSpace: Container(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: [_blue, _cyan]),
          ),
        ),
        iconTheme: IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [
          // Category Tabs
          Container(
            color: Colors.white,
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: _categories.map((c) {
                  bool isSelected = _selectedCategory == c['id'];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 4.0),
                    child: ChoiceChip(
                      label: Text(c['label']!, style: TextStyle(fontFamily: 'Cairo')),
                      selected: isSelected,
                      selectedColor: _blue.withValues(alpha: 0.2),
                      onSelected: (val) {
                        if (val) {
                          setState(() => _selectedCategory = c['id']!);
                          _loadItems();
                        }
                      },
                    ),
                  );
                }).toList(),
              ),
            ),
          ),
          
          // Filters for Sections
          if (_selectedCategory == 'Sections')
            Container(
              padding: EdgeInsets.all(8),
              color: Colors.white,
              child: Row(
                children: [
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedProfileId,
                      decoration: InputDecoration(labelText: 'البروفيل', contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder()),
                      items: _profiles.map((p) => DropdownMenuItem<int>(value: p['id'], child: Text(p['name']))).toList(),
                      onChanged: (val) {
                        if (val != null) _loadSeriesForProfile(val);
                      },
                    ),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: DropdownButtonFormField<int>(
                      value: _selectedSeriesId,
                      decoration: InputDecoration(labelText: 'السلسلة', contentPadding: EdgeInsets.symmetric(horizontal: 10), border: OutlineInputBorder()),
                      items: _seriesList.map((s) => DropdownMenuItem<int>(value: s['id'], child: Text(s['name']))).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSeriesId = val);
                          _loadItems();
                        }
                      },
                    ),
                  ),
                ],
              ),
            ),

          // Search Field
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
            child: TextField(
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث بالاسم أو الكود (مثال: بروليكس كادر)...',
                prefixIcon: Icon(Icons.search, color: _blue),
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: Colors.grey.shade300),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: _blue),
                ),
              ),
              onChanged: (val) => _loadItems(),
            ),
          ),

          // Items List
          Expanded(
            child: _isLoading 
                ? Center(child: CircularProgressIndicator())
                : ListView.builder(
                    padding: EdgeInsets.all(12),
                    itemCount: _items.length,
                    itemBuilder: (context, index) {
                      final item = _items[index];
                      String title = item['name'] ?? item['type'] ?? '';
                      // If it's a section and it has a profile_name (from global search), prepend it
                      if (item.containsKey('profile_name') && item['profile_name'] != null) {
                        title = '${item['profile_name']} - $title';
                      }
                      return Card(
                        elevation: 1,
                        margin: EdgeInsets.only(bottom: 8),
                        child: ListTile(
                          title: Text(title, style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold)),
                          subtitle: Text(item['code'] ?? '', style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                          trailing: IconButton(
                            icon: Icon(Icons.add_circle, color: _blue),
                            onPressed: () => _showAddItemDialog(item),
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
