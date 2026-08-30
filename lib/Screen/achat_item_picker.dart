import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';

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

  // 🟢 اختصار الأسماء لتوفير المساحة في الشاشات الصغيرة
  final List<Map<String, String>> _categories = [
    {'id': 'Sections', 'label': 'مقاطع'},
    {'id': 'Accessories', 'label': 'إكسسوارات'},
    {'id': 'ShutterComponents', 'label': 'مركبات الستائر'},
    {'id': 'Glass', 'label': 'زجاج'},
    {'id': 'Joints', 'label': 'جوانات'},
  ];

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;

  bool _itemsAdded = false;

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
        items = await _db.searchSectionsWithProfile(query);
      } else if (_selectedSeriesId != null) {
        items = await _db.readSectionsBySeries(_selectedSeriesId!);
      }
    } else if (_selectedCategory == 'Accessories') {
      items = await _db.readAccessories();
    } else if (_selectedCategory == 'ShutterComponents') {
      items = await _db.readShutterComponents();
    } else if (_selectedCategory == 'Glass') {
      items = await _db.readGlass();
    } else if (_selectedCategory == 'Joints') {
      items = await _db.readJoints();
    }

    if (query.isNotEmpty && _selectedCategory != 'Sections') {
      items = items.where((item) {
        String name = (item['name'] ?? item['type'] ?? '')
            .toString()
            .toLowerCase();
        String code = (item['code'] ?? '').toString().toLowerCase();
        return name.contains(query) || code.contains(query);
      }).toList();
    }

    setState(() {
      _items = items;
      _isLoading = false;
    });
  }

  void _showAddItemDialog(Map<String, dynamic> item) async {
    List<Map<String, dynamic>> colors = [];
    int? selectedColorId;
    double defaultPrice = 0.0;

    if (_selectedCategory == 'Sections') {
      // الحصول على الألوان المرتبطة بالبروفيل فقط
      final int? sectionProfileId =
          item['profile_id'] as int? ?? _selectedProfileId;
      if (sectionProfileId != null) {
        colors = await _db.getColorsForProfile(sectionProfileId);
      }
      // إذا لم تكن هناك ألوان مرتبطة بالبروفيل فارجع إلى كل الألوان
      if (colors.isEmpty) {
        colors = await _db.readColors();
      }
      if (colors.isNotEmpty) {
        selectedColorId = colors.first['id'];

        // 1. البحث عن سعر المقطع المخصص أولاً
        defaultPrice = await _db.getSectionColorPrice(
          item['id'],
          selectedColorId!,
        );

        // 🟢 2. الحساب الصحيح: إذا لم يجد سعر للمقطع، يحسبه من السلسلة (سعر المتر × طول العود)
        if (defaultPrice == 0.0 && item['series_id'] != null) {
          double seriesPrice = await _db.getSeriesColorPrice(
            item['series_id'],
            selectedColorId!,
          );
          if (seriesPrice > 0.0) {
            double length =
                (item['bar_length'] as num?)?.toDouble() ??
                5.8; // طول العود الافتراضي 5.8
            defaultPrice = seriesPrice * length;
          }
        }
      }
    } else if (_selectedCategory == 'Accessories') {
      defaultPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
    } else if (_selectedCategory == 'ShutterComponents') {
      defaultPrice = (item['price'] as num?)?.toDouble() ?? 0.0;
    } else if (_selectedCategory == 'Glass') {
      defaultPrice = (item['price_per_sqm'] as num?)?.toDouble() ?? 0.0;
    } else if (_selectedCategory == 'Joints') {
      defaultPrice = (item['price_per_meter'] as num?)?.toDouble() ?? 0.0;
    }

    if (!mounted) return;

    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(
      text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(2) : '',
    );

    showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final lang = Provider.of<AppSettingsProvider>(context).language;
            return AlertDialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: Text(
                '${Localization.translate('إضافة: ', lang)}${Localization.translate(item['name'] ?? item['type'] ?? '', lang)}',
                style: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (_selectedCategory == 'Sections' &&
                        colors.isNotEmpty) ...[
                      DropdownButtonFormField<int>(
                        isExpanded: true,
                        initialValue: selectedColorId,
                        decoration: InputDecoration(
                          labelText: Localization.translate('اللون', lang),
                          border: OutlineInputBorder(),
                        ),
                        items: colors
                            .map(
                              (c) => DropdownMenuItem<int>(
                                value: c['id'],
                                child: Text(
                                  Localization.translate(c['name'], lang),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) async {
                          setDialogState(() => selectedColorId = val);
                          if (val != null) {
                            // 🟢 إعادة الحساب الصحيحة عند تغيير اللون
                            double newP = await _db.getSectionColorPrice(
                              item['id'],
                              val,
                            );
                            if (newP == 0.0 && item['series_id'] != null) {
                              double seriesPrice = await _db
                                  .getSeriesColorPrice(item['series_id'], val);
                              if (seriesPrice > 0.0) {
                                double length =
                                    (item['bar_length'] as num?)?.toDouble() ??
                                    5.8;
                                newP = seriesPrice * length;
                              }
                            }
                            if (newP > 0)
                              setDialogState(
                                () => priceCtrl.text = newP.toStringAsFixed(2),
                              );
                          }
                        },
                      ),
                      const SizedBox(height: 12),
                    ],
                    TextField(
                      controller: qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: _selectedCategory == 'Sections'
                            ? Localization.translate('الكمية (عدد)', lang)
                            : Localization.translate('الكمية', lang),
                        border: const OutlineInputBorder(),
                        prefixIcon: const Icon(Icons.format_list_numbered),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: priceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: Localization.translate('السعر للوحدة', lang),
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.attach_money),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(backgroundColor: _blue),
                  onPressed: () async {
                    double qty =
                        double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ??
                        1.0;
                    double price =
                        double.tryParse(priceCtrl.text.replaceAll(',', '.')) ??
                        0.0;
                    final itemId = (item['id'] as int?) ?? 0;

                    if (qty > 0 && price >= 0) {
                      final alreadyExists = await _db.achatItemExists(
                        achatId: widget.achatId,
                        itemId: itemId,
                        itemType: _selectedCategory,
                        colorId: selectedColorId,
                      );

                      if (alreadyExists) {
                        if (context.mounted) {
                          Navigator.pop(context);
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                Localization.translate('هذا العنصر موجود بالفعل في الفاتورة', lang),
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                              backgroundColor: Colors.orange,
                              duration: const Duration(seconds: 2),
                            ),
                          );
                        }
                        return;
                      }

                      await _db.insertAchatItem(
                        achatId: widget.achatId,
                        itemCode:
                            item['code'] ??
                            item['name'] ??
                            item['type'] ??
                            'Unknown',
                        itemName: item['name'] ?? item['type'] ?? 'Unknown',
                        itemType: _selectedCategory,
                        itemId: itemId,
                        colorId: selectedColorId,
                        quantity: qty,
                        price: price,
                      );

                      // تحديث المخزون إذا كانت الفاتورة مؤكدة
                      final achatRows = await _db.db.then(
                        (d) => d!.query(
                          'Achats',
                          where: 'id=?',
                          whereArgs: [widget.achatId],
                        ),
                      );
                      if (achatRows.isNotEmpty) {
                        final achat = achatRows.first;
                        final status = achat['status'] as String? ?? '';
                        final locationId = achat['location_id'] as int? ?? 1;
                        double currentTotal =
                            (achat['total'] as num?)?.toDouble() ?? 0.0;
                        double addedValue = qty * price;
                        await _db.db.then(
                          (d) => d!.update(
                            'Achats',
                            {'total': currentTotal + addedValue},
                            where: 'id=?',
                            whereArgs: [widget.achatId],
                          ),
                        );
                        if (status == 'Confirmed') {
                          await _db.updateInventory(
                            itemId: itemId,
                            itemType: _selectedCategory,
                            colorId: selectedColorId,
                            locationId: locationId,
                            quantityChange: qty,
                            transactionType: 'Purchase Add Item',
                            referenceId: widget.achatId,
                          );
                        }
                      }

                      if (context.mounted) {
                        Navigator.pop(context);
                        setState(() {
                          _itemsAdded = true;
                        });
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              Localization.translate('تم إضافة العنصر بنجاح!', lang),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            backgroundColor: Colors.green,
                            duration: const Duration(seconds: 1),
                          ),
                        );
                      }
                    }
                  },
                  child: Text(
                    Localization.translate('إضافة للفاتورة', lang),
                    style: const TextStyle(
                      color: Colors.white,
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        Navigator.pop(context, _itemsAdded);
      },
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(
          backgroundColor: Theme.of(context).scaffoldBackgroundColor,
          appBar: AppBar(
            title: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                Localization.translate('المستودع (إضافة للفاتورة)', lang),
                style: TextStyle(
                  fontFamily: 'Cairo',
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            flexibleSpace: Container(
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [_blue, _cyan]),
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            leading: IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded),
              onPressed: () => Navigator.pop(context, _itemsAdded),
            ),
          ),
          body: Column(
            children: [
              // 🟢 الصف الأول: حقل "الصنف" + حقل "البروفيل"
              Padding(
                padding: const EdgeInsets.only(top: 12, left: 12, right: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<String>(
                        isExpanded: true,
                        value: _selectedCategory,
                        decoration: InputDecoration(
                          labelText: Localization.translate('الصنف', lang),
                          labelStyle: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                          border: OutlineInputBorder(),
                          contentPadding: EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 8,
                          ),
                        ),
                        items: _categories
                            .map(
                              (c) => DropdownMenuItem(
                                value: c['id'],
                                child: Text(
                                  Localization.translate(c['label']!, lang),
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            )
                            .toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedCategory = val);
                            _loadItems();
                          }
                        },
                      ),
                    ),

                    if (_selectedCategory == 'Sections') ...[
                      const SizedBox(width: 8),
                      Expanded(
                        child: DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: _selectedProfileId,
                          decoration: InputDecoration(
                            labelText: Localization.translate('البروفيل', lang),
                            labelStyle: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                            ),
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                          ),
                          items: _profiles
                              .map(
                                (p) => DropdownMenuItem<int>(
                                  value: p['id'],
                                  child: Text(
                                    p['name'] ?? '',
                                    style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 13,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              )
                              .toList(),
                          onChanged: (val) {
                            if (val != null) _loadSeriesForProfile(val);
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // 🟢 الصف الثاني: حقل "السلسلة"
              if (_selectedCategory == 'Sections' && _seriesList.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
                  child: DropdownButtonFormField<int>(
                    isExpanded: true,
                    value: _selectedSeriesId,
                    decoration: InputDecoration(
                      labelText: Localization.translate('السلسلة (Série)', lang),
                      labelStyle: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                      border: OutlineInputBorder(),
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    items: _seriesList
                        .map(
                          (s) => DropdownMenuItem<int>(
                            value: s['id'],
                            child: Text(
                              s['name'] ?? '',
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 13,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        )
                        .toList(),
                    onChanged: (val) {
                      if (val != null) {
                        setState(() => _selectedSeriesId = val);
                        _loadItems();
                      }
                    },
                  ),
                ),

              // 🟢 الصف الثالث: حقل البحث
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12.0,
                  vertical: 12.0,
                ),
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    labelText: Localization.translate('البحث عن المادة...', lang),
                    hintText: Localization.translate('مثال: كادر، أوفرو...', lang),
                    hintStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                    ),
                    prefixIcon: Icon(Icons.search, color: _blue),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, color: Colors.grey),
                            onPressed: () {
                              _searchCtrl.clear();
                              _loadItems();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Theme.of(context).cardColor,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 10,
                    ),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade300),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade300),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: _blue),
                    ),
                  ),
                  onChanged: (val) => _loadItems(),
                ),
              ),

              // 🟢 قائمة النتائج
              Expanded(
                child: _isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : _items.isEmpty
                    ? Center(
                        child: Text(
                          Localization.translate('لا توجد عناصر مطابقة', lang),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: Colors.grey.shade600,
                          ),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        itemCount: _items.length,
                        itemBuilder: (context, index) {
                          final item = _items[index];
                          String title = Localization.translate(item['name'] ?? item['type'] ?? '', lang);
                          String profileName = item['profile_name'] ?? '';

                          if (profileName.isEmpty &&
                              _selectedCategory == 'Sections' &&
                              _selectedProfileId != null) {
                            try {
                              profileName = Localization.translate(_profiles.firstWhere(
                                (p) => p['id'] == _selectedProfileId,
                              )['name'] ?? '', lang);
                            } catch (_) {}
                          }

                          if (profileName.isNotEmpty &&
                              _selectedCategory == 'Sections') {
                            title = '$profileName - $title';
                          }

                          return Card(
                            elevation: 0.5,
                            margin: const EdgeInsets.only(bottom: 8),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10),
                              side: BorderSide(color: Theme.of(context).brightness == Brightness.dark ? Colors.grey.shade800 : Colors.grey.shade200),
                            ),
                            child: ListTile(
                              title: Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              subtitle: Text(
                                item['code'] ?? '',
                                style: TextStyle(
                                  color: Theme.of(context).brightness == Brightness.dark ? Colors.white70 : Colors.grey[600],
                                  fontSize: 12,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              trailing: IconButton(
                                icon: Icon(
                                  Icons.add_circle,
                                  color: _blue,
                                  size: 32,
                                ),
                                tooltip: Localization.translate(
                                  'إضافة للفاتورة',
                                  lang,
                                ),
                                onPressed: () => _showAddItemDialog(item),
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
