import re

file_path = "lib/Screen/inventory_screen.dart"
with open(file_path, "r", encoding="utf-8") as f:
    content = f.read()

# I will find the end of `_loadLocations()`
loc_end = content.find("_locations.first['name']?.toString()")
loc_end_brace = content.find("setState(", loc_end) 
# wait, my corrupted file has this at line 66:
#           _selectedLocationName =
#               _locations.first['name']?.toString() ?? 'O U,U.O3OU^O_O1 O U,OOUSO3US';
#               ),
#             ),
#           ],

# Let's completely wipe the contents and rebuild it based on my knowledge of the file.
new_code = """import 'package:flutter/material.dart';
import '../sql_database.dart';
import 'inventory_item_history_screen.dart';
import 'inventory_adjustment_screen.dart';

class InventoryScreen extends StatefulWidget {
  final SqlDatabase db;

  const InventoryScreen({super.key, required this.db});

  @override
  State<InventoryScreen> createState() => _InventoryScreenState();
}

class _InventoryScreenState extends State<InventoryScreen> {
  List<Map<String, dynamic>> _locations = [];
  int? _selectedLocationId;
  String _selectedLocationName = '';

  List<Map<String, dynamic>> _stockData = [];
  List<Map<String, dynamic>> _filteredStockData = [];
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;
  double _totalValue = 0.0;
  bool _showAllItems = false;

  // Colors
  static const _blue = Color(0xFF2563EB);
  static const _cyan = Color(0xFF0EA5E9);
  static const _bg = Color(0xFFF8FAFC);
  static const _cardBg = Colors.white;
  static const _text = Color(0xFF1E293B);
  static const _textDim = Color(0xFF64748B);
  static const _divider = Color(0xFFE2E8F0);

  @override
  void initState() {
    super.initState();
    _loadLocations();
  }

  Future<void> _loadLocations() async {
    final locs = await widget.db.readLocations();
    if (mounted) {
      setState(() {
        _locations = locs;
        if (_locations.isNotEmpty) {
          _selectedLocationId = _locations.first['id'] as int;
          _selectedLocationName =
              _locations.first['name']?.toString() ?? 'المستودع الرئيسي';
          _loadStockData();
        } else {
          _isLoading = false;
        }
      });
    }
  }

  Future<void> _loadStockData() async {
    if (_selectedLocationId == null) return;
    setState(() => _isLoading = true);

    final data = _showAllItems
        ? await widget.db.readAllPossibleStock(_selectedLocationId!)
        : await widget.db.readCurrentStock(_selectedLocationId!);
    
    double totalValue = 0.0;

    for (var item in data) {
      final itemType = item['item_type'] as String;
      final itemId = item['item_id'] as int;
      final colorId = item['color_id'] as int?;
      final quantity = (item['quantity'] as num).toDouble();

      double price = 0.0;
      if (itemType == 'Sections' || itemType == 'Section' || itemType == 'Profile') {
        if (colorId != null) {
          price = await widget.db.getSectionColorPrice(itemId, colorId);
          if (price == 0.0) {
            final db = await widget.db.db;
            final secList = await db!.query(
              'Sections',
              where: 'id = ?',
              whereArgs: [itemId],
            );
            if (secList.isNotEmpty) {
              final seriesId = secList.first['series_id'] as int?;
              if (seriesId != null) {
                double sPrice = await widget.db.getSeriesColorPrice(
                  seriesId,
                  colorId,
                );
                if (sPrice > 0) {
                  double length =
                      (secList.first['bar_length'] as num?)?.toDouble() ?? 5.8;
                  price = sPrice * length;
                }
              }
            }
          }
        }
      } else if (itemType == 'Accessories' || itemType == 'Accessory') {
        final db = await widget.db.db;
        final resList = await db!.query(
          'Accessories',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (resList.isNotEmpty)
          price = (resList.first['price'] as num?)?.toDouble() ?? 0.0;
      } else if (itemType == 'Glass') {
        final db = await widget.db.db;
        final resList = await db!.query(
          'Glass',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (resList.isNotEmpty)
          price = (resList.first['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
      } else if (itemType == 'Shutter Component' ||
          itemType == 'ShutterComponents' ||
          itemType == 'ShutterComponent' ||
          itemType == 'Lame' ||
          itemType == 'Glissiere' ||
          itemType == 'Axe' ||
          itemType == 'Caisson') {
        final db = await widget.db.db;
        final resList = await db!.query(
          'ShutterComponents',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (resList.isNotEmpty)
          price = (resList.first['price'] as num?)?.toDouble() ?? 0.0;
      } else if (itemType == 'Joints' || itemType == 'Joint') {
        final db = await widget.db.db;
        final resList = await db!.query(
          'Joints',
          where: 'id = ?',
          whereArgs: [itemId],
        );
        if (resList.isNotEmpty)
          price = (resList.first['price_per_meter'] as num?)?.toDouble() ?? 0.0;
      }

      totalValue += (price * quantity);
    }

    if (mounted) {
      setState(() {
        _stockData = data;
        _filteredStockData = data;
        _totalValue = totalValue;
        _isLoading = false;
      });
      _filterStock();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildLocationDropdown(),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('المتوفر فقط'),
                            selected: !_showAllItems,
                            onSelected: (val) {
                              if (val) {
                                setState(() => _showAllItems = false);
                                _loadStockData();
                              }
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ChoiceChip(
                            label: const Text('كل العناصر'),
                            selected: _showAllItems,
                            onSelected: (val) {
                              if (val) {
                                setState(() => _showAllItems = true);
                                _loadStockData();
                              }
                            },
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _buildTotalValueCard(),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (value) => _filterStock(),
                      decoration: InputDecoration(
                        hintText: 'البحث عن عنصر، مقطع، لون...',
                        prefixIcon: const Icon(Icons.search, color: _blue),
                        filled: true,
                        fillColor: Colors.white,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _divider),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: _divider),
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    _buildStockList(),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar() {
    return SliverAppBar(
      expandedHeight: 150.0,
      pinned: true,
      backgroundColor: Colors.white,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_rounded, color: Colors.white),
        onPressed: () => Navigator.pop(context),
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.inventory, color: Colors.white),
          tooltip: 'جرد سنوي / تعديل المخزون',
          onPressed: () {
            if (_selectedLocationId != null) {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => InventoryAdjustmentScreen(
                    db: widget.db,
                    locationId: _selectedLocationId!,
                    locationName: _selectedLocationName,
                  ),
                ),
              ).then((_) => _loadStockData());
            }
          },
        ),
      ],
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_blue, _cyan],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: const Stack(
            children: [
              Positioned(
                right: -20,
                top: -20,
                child: CircleAvatar(
                  radius: 80,
                  backgroundColor: Colors.white10,
                ),
              ),
              Positioned(
                left: 10,
                bottom: -30,
                child: CircleAvatar(
                  radius: 60,
                  backgroundColor: Colors.white10,
                ),
              ),
            ],
          ),
        ),
        title: const Text(
          'المخزون (Inventory)',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: 18,
            color: Colors.white,
          ),
        ),
        titlePadding: const EdgeInsets.only(right: 56, bottom: 16),
        centerTitle: false,
      ),
    );
  }

  Widget _buildTotalValueCard() {
    if (_isLoading) return const SizedBox.shrink();

    String formattedTotal = _totalValue.toStringAsFixed(2);
    if (_totalValue == _totalValue.truncateToDouble()) {
      formattedTotal = _totalValue.toInt().toString();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(colors: [_blue, _cyan]),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 24,
              ),
              SizedBox(width: 8),
              Text(
                'القيمة الإجمالية للمخزون',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontWeight: FontWeight.w600,
                  fontSize: 16,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            '$formattedTotal DZD',
            style: const TextStyle(
              fontFamily: 'Cairo',
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 28,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLocationDropdown() {
    if (_locations.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      decoration: BoxDecoration(
        color: _cardBg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _divider),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _selectedLocationId,
          isExpanded: true,
          icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _textDim),
          items: _locations.map((loc) {
            return DropdownMenuItem<int>(
              value: loc['id'] as int,
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, color: _blue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    loc['name'],
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 15,
                      color: _text,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
          onChanged: (val) {
            if (val != null) {
              setState(() {
                _selectedLocationId = val;
                _selectedLocationName = _locations.firstWhere(
                  (l) => l['id'] == val,
                )['name']?.toString() ?? 'المستودع الرئيسي';
              });
              _loadStockData();
            }
          },
        ),
      ),
    );
  }

  Widget _buildStockList() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_filteredStockData.isEmpty) {
      return Center(
        child: Column(
          children: [
            const SizedBox(height: 40),
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: _blue.withValues(alpha: 0.3),
            ),
            const SizedBox(height: 16),
            const Text(
              'لا توجد عناصر في هذا المخزون',
              style: TextStyle(
                fontFamily: 'Cairo',
                color: _textDim,
                fontSize: 16,
              ),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _filteredStockData.length,
      itemBuilder: (context, index) {
        final item = _filteredStockData[index];
        final itemId = item['item_id'] as int;
        final itemType = item['item_type'] as String;
        final itemName = item['item_name'] as String;
        final colorId = item['color_id'] as int?;
        final colorName = item['color_name'] as String;
        final quantity = (item['quantity'] as num).toDouble();

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _cardBg,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: _divider),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.02),
                blurRadius: 8,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(16),
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => InventoryItemHistoryScreen(
                      db: widget.db,
                      itemId: itemId,
                      itemType: itemType,
                      itemName: itemName,
                      colorId: colorId,
                      colorName: colorName,
                      locationId: _selectedLocationId!,
                      locationName: _selectedLocationName,
                    ),
                  ),
                );
              },
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: _blue.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.category_rounded, color: _blue),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            itemName,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _text,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Text(
                                itemType,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: _textDim,
                                ),
                              ),
                              if (colorName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                const Icon(
                                  Icons.circle,
                                  size: 4,
                                  color: _divider,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  colorName,
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: _textDim,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text(
                          'الرصيد',
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: _textDim,
                          ),
                        ),
                        Text(
                          quantity.toStringAsFixed(
                            quantity.truncateToDouble() == quantity ? 0 : 2,
                          ),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w900,
                            fontSize: 18,
                            color: quantity > 0 ? _text : Colors.red,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    const Icon(
                      Icons.arrow_forward_ios_rounded,
                      size: 14,
                      color: _divider,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _filterStock() {
    final query = _searchCtrl.text.trim().toLowerCase();
    setState(() {
      if (query.isEmpty) {
        _filteredStockData = List.from(_stockData);
      } else {
        _filteredStockData = _stockData.where((item) {
          final name = (item['item_name'] ?? '').toString().toLowerCase();
          final type = (item['item_type'] ?? '').toString().toLowerCase();
          final color = (item['color_name'] ?? '').toString().toLowerCase();
          return name.contains(query) ||
              type.contains(query) ||
              color.contains(query);
        }).toList();
      }
    });
  }
}
"""

with open(file_path, "w", encoding="utf-8") as f:
    f.write(new_code)
