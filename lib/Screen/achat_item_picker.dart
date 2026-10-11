import 'package:database_data/widgets/app_material.dart';
import 'package:provider/provider.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import 'dart:async';

class AchatItemPicker extends StatefulWidget {
  final int achatId;
  final bool isEmbedded;
  final VoidCallback? onItemAdded;
  final VoidCallback? onClose;

  const AchatItemPicker({
    super.key,
    required this.achatId,
    this.isEmbedded = false,
    this.onItemAdded,
    this.onClose,
  });

  @override
  State<AchatItemPicker> createState() => _AchatItemPickerState();
}

class _AchatItemPickerState extends State<AchatItemPicker> {
  final SqlDatabase _db = SqlDatabase();
  final Color _blue = const Color(0xFF1E3A8A);
  final Color _cyan = const Color(0xFF06B6D4);

  // الفلترة مبدئياً غير مفعلة (الكل)
  String _selectedCategory = 'All';

  final List<Map<String, String>> _categories = [
    {'id': 'All', 'label': 'كل المواد'},
    {'id': 'Sections', 'label': 'مقاطع'},
    {'id': 'Accessories', 'label': 'إكسسوارات'},
    {'id': 'ShutterComponents', 'label': 'مركبات الستائر'},
    {'id': 'Glass', 'label': 'ألواح زجاج'},
    {'id': 'Joints', 'label': 'جوانات'},
  ];

  List<Map<String, dynamic>> _items = [];
  bool _isLoading = false;
  bool _itemsAdded = false;
  Timer? _searchDebounce;

  // Filters (مبدئياً null تعني غير مفعلة / الكل)
  int? _selectedProfileId;
  int? _selectedSeriesId;
  List<Map<String, dynamic>> _profiles = [];
  List<Map<String, dynamic>> _seriesList = [];

  final TextEditingController _searchCtrl = TextEditingController();

  // ذاكرة مؤقتة للألوان والأسعار لتسريع البحث بشكل فائق
  final Map<int, List<Map<String, dynamic>>> _profileColorsCache = {};
  List<Map<String, dynamic>>? _allColorsCache;
  Map<String, dynamic>? _rawColorRow;
  final Map<int, int?> _seriesProfileCache = {};

  @override
  void initState() {
    super.initState();
    _loadFilters();
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadFilters() async {
    final profiles = await _db.readProfile();
    if (mounted) {
      setState(() {
        _profiles = profiles;
        _selectedProfileId = null;
        _selectedSeriesId = null;
        _seriesList = [];
      });
    }
    await _loadItems();
  }

  Future<void> _loadSeriesForProfile(int? profileId) async {
    if (profileId == null) {
      if (mounted) {
        setState(() {
          _seriesList = [];
          _selectedSeriesId = null;
        });
      }
      return;
    }
    final series = await _db.readSeriesByProfile(profileId);
    if (mounted) {
      setState(() {
        _seriesList = series;
        _selectedSeriesId = null;
      });
    }
  }

  Future<Map<String, dynamic>?> _getRawColorRow() async {
    if (_rawColorRow != null) return _rawColorRow;
    final myDb = await _db.db;
    if (myDb == null) return null;
    final rows = await myDb.query(
      'Colors',
      where: "name = ? OR name LIKE ?",
      whereArgs: ['خام', '%brut%'],
      limit: 1,
    );
    if (rows.isNotEmpty) {
      _rawColorRow = rows.first;
    }
    return _rawColorRow;
  }

  Future<List<Map<String, dynamic>>> _getProfileColors(int? profileId) async {
    if (profileId != null && _profileColorsCache.containsKey(profileId)) {
      return _profileColorsCache[profileId]!;
    }

    List<Map<String, dynamic>> colors = [];
    if (profileId != null) {
      colors = await _db.getColorsForProfile(profileId);
    }
    if (colors.isEmpty) {
      _allColorsCache ??= await _db.readColors();
      colors = _allColorsCache ?? [];
    }

    // التأكد من توفر اللون الخام (Brut) دائماً مع ألوان السلسلة
    final hasRaw = colors.any((c) {
      final name = (c['name'] ?? '').toString().trim();
      return name == 'خام' || name.toLowerCase().contains('brut');
    });

    if (!hasRaw) {
      final rawRow = await _getRawColorRow();
      if (rawRow != null) {
        colors = [...colors, rawRow];
      } else {
        colors = [
          ...colors,
          {'id': 0, 'name': 'خام', 'hex_code': '#D1D5DB'},
        ];
      }
    }

    if (profileId != null) {
      _profileColorsCache[profileId] = colors;
    }
    return colors;
  }

  Future<int?> _getProfileIdForSeries(int seriesId) async {
    if (_seriesProfileCache.containsKey(seriesId)) {
      return _seriesProfileCache[seriesId];
    }
    final myDb = await _db.db;
    if (myDb == null) return null;
    final rows = await myDb.query(
      'Series',
      columns: ['profile_id'],
      where: 'id = ?',
      whereArgs: [seriesId],
      limit: 1,
    );
    int? pId;
    if (rows.isNotEmpty) {
      pId = (rows.first['profile_id'] as num?)?.toInt();
    }
    _seriesProfileCache[seriesId] = pId;
    return pId;
  }

  Future<void> _loadItems() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    final query = _searchCtrl.text.trim().toLowerCase();
    List<Map<String, dynamic>> resultItems = [];

    // ── 1. المقاطع (Sections) ────────────────────────────────────────────────
    if (_selectedCategory == 'All' || _selectedCategory == 'Sections') {
      List<Map<String, dynamic>> rawSections = [];
      if (query.isNotEmpty) {
        rawSections = await _db.searchSectionsWithProfile(query);
      } else if (_selectedSeriesId != null) {
        rawSections = await _db.readSectionsBySeries(_selectedSeriesId!);
      } else {
        rawSections = await _db.searchSectionsWithProfile('');
      }

      if (_selectedProfileId != null) {
        rawSections = rawSections.where((s) {
          final pId = (s['source_profile_id'] ?? s['profile_id']) as int?;
          return pId == _selectedProfileId;
        }).toList();
      }
      if (_selectedSeriesId != null) {
        rawSections = rawSections.where((s) {
          final sId = (s['source_series_id'] ?? s['series_id']) as int?;
          return sId == _selectedSeriesId;
        }).toList();
      }

      // تمديد المقاطع لكل لون من ألوان السلسلة (Expansion per color)
      for (var s in rawSections) {
        final pId = (s['source_profile_id'] ?? s['profile_id']) as int?;
        final profileColors = await _getProfileColors(pId);
        final barLength = (s['bar_length'] as num?)?.toDouble() ?? 5.8;
        final seriesId = (s['source_series_id'] ?? s['series_id']) as int?;

        if (profileColors.isNotEmpty) {
          for (var c in profileColors) {
            final colorId = (c['id'] as num?)?.toInt();
            final colorName = c['name']?.toString() ?? '';

            // السعر الافتراضي = آخر سعر اشترينا به لهذا المقطع واللون تحديداً
            // إلغاء الاستعلامات المتكررة لتسريع الفتح، وسيتم جلب السعر عند الضغط على الصنف
            double price = (s['purchase_price'] as num?)?.toDouble() ?? 0.0;

            resultItems.add({
              'id': s['id'],
              'code': s['code'] ?? '',
              'name': s['name'] ?? '',
              'type': s['type'] ?? '',
              'item_type': 'Sections',
              'category_label': 'مقاطع',
              'profile_name': s['profile_name'] ?? '',
              'series_name': s['series_name'] ?? '',
              'profile_id': pId,
              'series_id': seriesId,
              'bar_length': barLength,
              'expanded_color_id': colorId,
              'expanded_color_name': colorName,
              'expanded_color_hex': c['hex_code'],
              'default_price': price,
              'available_colors': profileColors,
              'raw_item': s,
            });
          }
        } else {
          resultItems.add({
            'id': s['id'],
            'code': s['code'] ?? '',
            'name': s['name'] ?? '',
            'type': s['type'] ?? '',
            'item_type': 'Sections',
            'category_label': 'مقاطع',
            'profile_name': s['profile_name'] ?? '',
            'series_name': s['series_name'] ?? '',
            'profile_id': pId,
            'series_id': seriesId,
            'bar_length': barLength,
            'default_price': 0.0,
            'available_colors': <Map<String, dynamic>>[],
            'raw_item': s,
          });
        }
      }
    }

    // ── 2. الإكسسوارات (Accessories) ─────────────────────────────────────────
    if (_selectedCategory == 'All' || _selectedCategory == 'Accessories') {
      var rawAccessories = await _db.readAccessories();
      if (query.isNotEmpty) {
        rawAccessories = rawAccessories.where((a) {
          final name = (a['name'] ?? '').toString().toLowerCase();
          final type = (a['type'] ?? '').toString().toLowerCase();
          final code = (a['code'] ?? '').toString().toLowerCase();
          return name.contains(query) ||
              type.contains(query) ||
              code.contains(query);
        }).toList();
      }
      if (_selectedSeriesId != null) {
        rawAccessories = rawAccessories.where((a) {
          final sId = a['series_id'] as int?;
          return sId == _selectedSeriesId;
        }).toList();
      }

      for (var a in rawAccessories) {
        final sId = a['series_id'] as int?;
        int? pId;
        if (sId != null) {
          pId = await _getProfileIdForSeries(sId);
        }
        final colors = await _getProfileColors(pId);
        final price = ((a['price'] as num?)?.toDouble() ?? 0.0);

        resultItems.add({
          'id': a['id'],
          'code': a['code'] ?? a['type'] ?? '',
          'name': a['name'] ?? '',
          'type': a['type'] ?? 'Accessory',
          'item_type': 'Accessories',
          'category_label': 'إكسسوارات',
          'profile_id': pId,
          'series_id': sId,
          'default_price': price,
          'available_colors': colors,
          'raw_item': a,
        });
      }
    }

    // ── 3. مركبات الستائر (Shutter Components) ──────────────────────────────
    if (_selectedCategory == 'All' ||
        _selectedCategory == 'ShutterComponents') {
      var rawShutters = await _db.readShutterComponents();
      if (query.isNotEmpty) {
        rawShutters = rawShutters.where((sc) {
          final name = (sc['name'] ?? '').toString().toLowerCase();
          final code = (sc['code'] ?? '').toString().toLowerCase();
          return name.contains(query) || code.contains(query);
        }).toList();
      }
      for (var sc in rawShutters) {
        final latest = await _db.getLatestPurchasePrice(
          itemId: sc['id'] as int,
          itemType: 'ShutterComponents',
        );
        final price = (latest != null && latest > 0)
            ? latest
            : ((sc['price'] as num?)?.toDouble() ?? 0.0);

        resultItems.add({
          'id': sc['id'],
          'code': sc['code'] ?? '',
          'name': sc['name'] ?? '',
          'type': 'ShutterComponent',
          'item_type': 'ShutterComponents',
          'category_label': 'مركبات الستائر',
          'default_price': price,
          'raw_item': sc,
        });
      }
    }

    // ── 4. ألواح الزجاج (Glass Sheets) ──────────────────────────────────────
    if (_selectedCategory == 'All' || _selectedCategory == 'Glass') {
      var rawGlass = await _db.readGlass();
      if (query.isNotEmpty) {
        rawGlass = rawGlass.where((g) {
          final name = (g['name'] ?? '').toString().toLowerCase();
          final type = (g['type'] ?? '').toString().toLowerCase();
          return name.contains(query) ||
              type.contains(query) ||
              'لوح زجاج'.contains(query) ||
              'verre'.contains(query);
        }).toList();
      }
      for (var g in rawGlass) {
        final latest = await _db.getLatestPurchasePrice(
          itemId: g['id'] as int,
          itemType: 'Glass',
        );
        final price = (latest != null && latest > 0)
            ? latest
            : ((g['price_per_sqm'] as num?)?.toDouble() ??
                  (g['price'] as num?)?.toDouble() ??
                  0.0);

        resultItems.add({
          'id': g['id'],
          'code': '${g['thickness'] ?? ''} mm',
          'name': 'لوح زجاج ${g['name'] ?? g['type'] ?? ''}',
          'type': g['type'] ?? 'Glass',
          'item_type': 'Glass',
          'category_label': 'ألواح زجاج',
          'default_price': price,
          'raw_item': g,
        });
      }
    }

    // ── 5. الجوانات (Joints) ─────────────────────────────────────────────────
    if (_selectedCategory == 'All' || _selectedCategory == 'Joints') {
      var rawJoints = await _db.readJoints();
      if (query.isNotEmpty) {
        rawJoints = rawJoints.where((j) {
          final name = (j['name'] ?? '').toString().toLowerCase();
          final code = (j['code'] ?? '').toString().toLowerCase();
          return name.contains(query) || code.contains(query);
        }).toList();
      }
      for (var j in rawJoints) {
        final latest = await _db.getLatestPurchasePrice(
          itemId: j['id'] as int,
          itemType: 'Joints',
        );
        final price = (latest != null && latest > 0)
            ? latest
            : ((j['price_per_meter'] as num?)?.toDouble() ??
                  (j['price'] as num?)?.toDouble() ??
                  0.0);

        resultItems.add({
          'id': j['id'],
          'code': j['code'] ?? '',
          'name': j['name'] ?? 'جوان',
          'type': 'Joint',
          'item_type': 'Joints',
          'category_label': 'جوانات',
          'default_price': price,
          'raw_item': j,
        });
      }
    }

    if (mounted) {
      setState(() {
        _items = resultItems;
        _isLoading = false;
      });
    }
  }

  void _showAddItemDialog(Map<String, dynamic> item) async {
    final itemType = item['item_type'] as String? ?? 'Sections';
    final List<Map<String, dynamic>> colors =
        (item['available_colors'] as List<dynamic>?)
            ?.cast<Map<String, dynamic>>() ??
        [];

    // اللون المحدد مبدئياً: إما اللون المختار من التوسعة أو أول لون متاح
    int? selectedColorId = item['expanded_color_id'] as int?;
    if (selectedColorId == null && colors.isNotEmpty) {
      selectedColorId = colors.first['id'] as int?;
    }

    double defaultPrice = (item['default_price'] as num?)?.toDouble() ?? 0.0;

    // تأكيد السعر من آخر عملية شراء إذا كان 0
    if (defaultPrice <= 0) {
      final latest = await _db.getLatestPurchasePrice(
        itemId: item['id'] as int,
        itemType: itemType,
        colorId: selectedColorId,
      );
      if (latest != null && latest > 0) {
        defaultPrice = latest;
      }
    }

    if (!mounted) return;

    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(
      text: defaultPrice > 0 ? defaultPrice.toStringAsFixed(2) : '',
    );

    // حارس لمنع النقر المتعدد أو الكراش (!_debugLocked)
    bool isSubmitting = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => Directionality(
        textDirection: TextDirection.rtl,
        child: StatefulBuilder(
          builder: (context, setDialogState) {
            final lang = Provider.of<AppSettingsProvider>(context).language;
            return AlertDialog(
              insetPadding: const EdgeInsets.all(16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: _blue.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.add_shopping_cart_rounded, color: _blue),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '${Localization.translate('إضافة: ', lang)}${Localization.translate(item['name'] ?? '', lang)}',
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
              content: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420, minWidth: 300),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      // قائمة الألوان: تظهر فقط ألوان السلسلة المحددة + خام
                      if ((itemType == 'Sections' ||
                              itemType == 'Accessories') &&
                          colors.isNotEmpty) ...[
                        DropdownButtonFormField<int>(
                          isExpanded: true,
                          value: selectedColorId,
                          decoration: InputDecoration(
                            labelText: Localization.translate('اللون', lang),
                            helperText: Localization.translate(
                              'ألوان السلسلة فقط + اللون الخام',
                              lang,
                            ),
                            border: const OutlineInputBorder(),
                            prefixIcon: const Icon(Icons.palette_outlined),
                          ),
                          items: colors.map((c) {
                            final colorHex = c['hex_code']?.toString();
                            Color? chipColor;
                            if (colorHex != null && colorHex.startsWith('#')) {
                              try {
                                chipColor = Color(
                                  int.parse(colorHex.replaceAll('#', '0xFF')),
                                );
                              } catch (_) {}
                            }
                            return DropdownMenuItem<int>(
                              value: c['id'] as int?,
                              child: Row(
                                children: [
                                  if (chipColor != null) ...[
                                    Container(
                                      width: 14,
                                      height: 14,
                                      decoration: BoxDecoration(
                                        color: chipColor,
                                        shape: BoxShape.circle,
                                        border: Border.all(
                                          color: Colors.black26,
                                          width: 0.8,
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                  ],
                                  Expanded(
                                    child: Text(
                                      Localization.translate(
                                        c['name'] ?? '',
                                        lang,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 13,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                          onChanged: isSubmitting
                              ? null
                              : (val) async {
                                  setDialogState(() => selectedColorId = val);
                                  if (val != null) {
                                    // التحقق أولاً من آخر سعر شراء مسجل لهذا اللون
                                    final latest = await _db
                                        .getLatestPurchasePrice(
                                          itemId: item['id'] as int,
                                          itemType: itemType,
                                          colorId: val,
                                        );
                                    if (latest != null && latest > 0) {
                                      setDialogState(() {
                                        priceCtrl.text = latest.toStringAsFixed(
                                          2,
                                        );
                                      });
                                      return;
                                    }

                                    // إذا لم يوجد سعر شراء سابق للمقطع، نحسب من الكتالوج
                                    if (itemType == 'Sections') {
                                      double newP = await _db
                                          .getSectionColorPrice(
                                            item['id'],
                                            val,
                                          );
                                      if (newP == 0.0 &&
                                          item['series_id'] != null) {
                                        double seriesPrice = await _db
                                            .getSeriesColorPrice(
                                              item['series_id'],
                                              val,
                                            );
                                        if (seriesPrice > 0.0) {
                                          double length =
                                              (item['bar_length'] as num?)
                                                  ?.toDouble() ??
                                              5.8;
                                          newP = seriesPrice * length;
                                        }
                                      }
                                      if (newP > 0) {
                                        setDialogState(() {
                                          priceCtrl.text = newP.toStringAsFixed(
                                            2,
                                          );
                                        });
                                      }
                                    }
                                  }
                                },
                        ),
                        const SizedBox(height: 14),
                      ],

                      // حقل الكمية
                      TextField(
                        controller: qtyCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: itemType == 'Sections'
                              ? Localization.translate(
                                  'الكمية (عدد القضبان)',
                                  lang,
                                )
                              : itemType == 'Glass'
                              ? Localization.translate(
                                  'الكمية (ألواح / م²)',
                                  lang,
                                )
                              : itemType == 'Joints'
                              ? Localization.translate(
                                  'الكمية (أمتار / بكرة)',
                                  lang,
                                )
                              : Localization.translate('الكمية', lang),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.format_list_numbered),
                        ),
                      ),
                      const SizedBox(height: 14),

                      // حقل السعر (افتراضياً آخر سعر شراء)
                      TextField(
                        controller: priceCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: Localization.translate(
                            'سعر الوحدة (دج)',
                            lang,
                          ),
                          helperText: Localization.translate(
                            'السعر تلقائياً هو آخر سعر شراء مسجل',
                            lang,
                          ),
                          border: const OutlineInputBorder(),
                          prefixIcon: const Icon(Icons.attach_money),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSubmitting
                      ? null
                      : () => Navigator.of(dialogContext).pop(),
                  child: Text(
                    Localization.translate('إلغاء', lang),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      color: Colors.grey.shade600,
                    ),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _blue,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  onPressed: isSubmitting
                      ? null
                      : () async {
                          if (isSubmitting) return;
                          setDialogState(() => isSubmitting = true);

                          final double qty =
                              double.tryParse(
                                qtyCtrl.text.replaceAll(',', '.'),
                              ) ??
                              1.0;
                          final double price =
                              double.tryParse(
                                priceCtrl.text.replaceAll(',', '.'),
                              ) ??
                              0.0;
                          final itemId = (item['id'] as int?) ?? 0;

                          if (qty <= 0) {
                            setDialogState(() => isSubmitting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'يرجى إدخال كمية صحيحة',
                                    lang,
                                  ),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.red,
                              ),
                            );
                            return;
                          }

                          try {
                            final alreadyExists = await _db.achatItemExists(
                              achatId: widget.achatId,
                              itemId: itemId,
                              itemType: itemType,
                              colorId: selectedColorId,
                            );

                            if (alreadyExists) {
                              if (dialogContext.mounted &&
                                  Navigator.canPop(dialogContext)) {
                                Navigator.of(dialogContext).pop();
                              }
                              if (mounted) {
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(
                                      Localization.translate(
                                        'هذا العنصر موجود بالفعل في الفاتورة',
                                        lang,
                                      ),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                      ),
                                    ),
                                    backgroundColor: Colors.orange,
                                    duration: const Duration(seconds: 2),
                                  ),
                                );
                              }
                              return;
                            }

                            // حفظ العنصر في قاعدة البيانات
                            await _db.insertAchatItem(
                              achatId: widget.achatId,
                              itemCode:
                                  item['code'] ??
                                  item['name'] ??
                                  item['type'] ??
                                  'Item',
                              itemName: item['name'] ?? item['type'] ?? 'Item',
                              itemType: itemType,
                              itemId: itemId,
                              colorId: selectedColorId,
                              quantity: qty,
                              price: price,
                            );

                            // تحديث إجمالي الفاتورة والمخزون إذا كانت مؤكدة
                            final achatRows = await _db.db.then(
                              (d) => d!.query(
                                'Achats',
                                where: 'id = ?',
                                whereArgs: [widget.achatId],
                              ),
                            );
                            if (achatRows.isNotEmpty) {
                              final achat = achatRows.first;
                              final status = achat['status'] as String? ?? '';
                              final locationId =
                                  achat['location_id'] as int? ?? 1;
                              double currentTotal =
                                  (achat['total'] as num?)?.toDouble() ?? 0.0;
                              double addedValue = qty * price;
                              await _db.db.then(
                                (d) => d!.update(
                                  'Achats',
                                  {'total': currentTotal + addedValue},
                                  where: 'id = ?',
                                  whereArgs: [widget.achatId],
                                ),
                              );
                              if (status == 'Confirmed') {
                                await _db.updateInventory(
                                  itemId: itemId,
                                  itemType: itemType,
                                  colorId: selectedColorId,
                                  locationId: locationId,
                                  quantityChange: qty,
                                  transactionType: 'Purchase Add Item',
                                  referenceId: widget.achatId,
                                  unitPrice: price,
                                );
                              }
                            }

                            // إشعار الصفحة الخلفية بتحديث الجدول فورياً
                            widget.onItemAdded?.call();

                            if (dialogContext.mounted &&
                                Navigator.canPop(dialogContext)) {
                              Navigator.of(dialogContext).pop();
                            }

                            if (mounted) {
                              setState(() => _itemsAdded = true);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    Localization.translate(
                                      'تم إضافة العنصر بنجاح وتحديث الجدول!',
                                      lang,
                                    ),
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  backgroundColor: Colors.green,
                                  duration: const Duration(seconds: 1),
                                ),
                              );
                            }
                          } catch (e) {
                            if (dialogContext.mounted) {
                              setDialogState(() => isSubmitting = false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    'حدث خطأ: $e',
                                    style: const TextStyle(fontFamily: 'Cairo'),
                                  ),
                                  backgroundColor: Colors.red,
                                ),
                              );
                            }
                          }
                        },
                  child: isSubmitting
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : Text(
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

  Widget _buildContent(BuildContext context, AppLanguage lang) {
    return Column(
      children: [
        // ── الصف الأول: حقل "الصنف" + حقل "البروفيل" ──────────────────────
        Padding(
          padding: const EdgeInsets.only(top: 10, left: 12, right: 12),
          child: Row(
            children: [
              Expanded(
                child: DropdownButtonFormField<String>(
                  isExpanded: true,
                  value: _selectedCategory,
                  decoration: InputDecoration(
                    labelText: Localization.translate('الصنف', lang),
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 8,
                    ),
                  ),
                  items: _categories.map((c) {
                    return DropdownMenuItem(
                      value: c['id'],
                      child: Text(
                        Localization.translate(c['label']!, lang),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    );
                  }).toList(),
                  onChanged: (val) {
                    if (val != null) {
                      setState(() {
                        _selectedCategory = val;
                      });
                      _loadItems();
                    }
                  },
                ),
              ),

              // حقل البروفيل (يظهر إذا كان الصنف 'All' أو 'Sections')
              if (_selectedCategory == 'All' ||
                  _selectedCategory == 'Sections') ...[
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<int?>(
                    isExpanded: true,
                    value: _selectedProfileId,
                    decoration: InputDecoration(
                      labelText: Localization.translate('البروفيل', lang),
                      labelStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                      border: const OutlineInputBorder(),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 8,
                      ),
                    ),
                    items: [
                      DropdownMenuItem<int?>(
                        value: null,
                        child: Text(
                          Localization.translate('كل البروفيلات', lang),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 12,
                            color: Colors.blueGrey,
                          ),
                        ),
                      ),
                      ..._profiles.map((p) {
                        return DropdownMenuItem<int?>(
                          value: p['id'] as int?,
                          child: Text(
                            p['name'] ?? '',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                    ],
                    onChanged: (val) {
                      setState(() {
                        _selectedProfileId = val;
                        _loadSeriesForProfile(val);
                      });
                      _loadItems();
                    },
                  ),
                ),
              ],
            ],
          ),
        ),

        // ── الصف الثاني: حقل "السلسلة" (إذا تم اختيار بروفيل) ──────────────
        if ((_selectedCategory == 'All' || _selectedCategory == 'Sections') &&
            _seriesList.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 8, left: 12, right: 12),
            child: DropdownButtonFormField<int?>(
              isExpanded: true,
              value: _selectedSeriesId,
              decoration: InputDecoration(
                labelText: Localization.translate('السلسلة (Série)', lang),
                labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                ),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
              ),
              items: [
                DropdownMenuItem<int?>(
                  value: null,
                  child: Text(
                    Localization.translate('كل السلاسل', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: Colors.blueGrey,
                    ),
                  ),
                ),
                ..._seriesList.map((s) {
                  return DropdownMenuItem<int?>(
                    value: s['id'] as int?,
                    child: Text(
                      s['name'] ?? '',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }),
              ],
              onChanged: (val) {
                setState(() => _selectedSeriesId = val);
                _loadItems();
              },
            ),
          ),

        // ── الصف الثالث: حقل البحث العام عبر كل الجداول ─────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12.0, vertical: 8.0),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              labelText: Localization.translate('البحث في كل المواد...', lang),
              hintText: Localization.translate(
                'ابحث بالاسم أو الكود (مقاطع، إكسسوارات، جوانات، زجاج...)',
                lang,
              ),
              hintStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              prefixIcon: Icon(Icons.search, color: _blue, size: 20),
              suffixIcon: _searchCtrl.text.isNotEmpty
                  ? IconButton(
                      icon: const Icon(
                        Icons.clear,
                        color: Colors.grey,
                        size: 18,
                      ),
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
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: Colors.grey.shade300),
              ),
            ),
            onChanged: (val) {
              _searchDebounce?.cancel();
              _searchDebounce = Timer(const Duration(milliseconds: 300), () {
                _loadItems();
              });
            },
          ),
        ),

        // ── قائمة النتائج ──────────────────────────────────────────────────
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
              ? Center(
                  child: Text(
                    Localization.translate('لا توجد مواد مطابقة للبحث', lang),
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
                    final itemType = item['item_type'] as String? ?? 'Other';
                    final categoryLabel =
                        item['category_label'] as String? ?? '';
                    final profileName = item['profile_name'] ?? '';
                    final colorName = item['expanded_color_name'] as String?;
                    final colorHex = item['expanded_color_hex'] as String?;
                    final double price =
                        (item['default_price'] as num?)?.toDouble() ?? 0.0;

                    String title = Localization.translate(
                      item['name'] ?? item['type'] ?? '',
                      lang,
                    );
                    if (profileName.isNotEmpty && itemType == 'Sections') {
                      title = '$profileName - $title';
                    }

                    Color? dotColor;
                    if (colorHex != null && colorHex.startsWith('#')) {
                      try {
                        dotColor = Color(
                          int.parse(colorHex.replaceAll('#', '0xFF')),
                        );
                      } catch (_) {}
                    }

                    return Card(
                      elevation: 0.5,
                      margin: const EdgeInsets.only(bottom: 6),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                        side: BorderSide(
                          color: Theme.of(context).brightness == Brightness.dark
                              ? Colors.grey.shade800
                              : Colors.grey.shade200,
                        ),
                      ),
                      child: ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 4,
                        ),
                        title: Row(
                          children: [
                            // شارة نوع الصنف
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _blue.withValues(alpha: 0.08),
                                borderRadius: BorderRadius.circular(4),
                              ),
                              child: Text(
                                Localization.translate(categoryLabel, lang),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                  color: _blue,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                title,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // شارة اللون إذا كان مقطع موسع بلون معين
                            if (colorName != null && colorName.isNotEmpty) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: (dotColor ?? Colors.blueGrey)
                                      .withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: dotColor ?? Colors.blueGrey,
                                    width: 1,
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (dotColor != null) ...[
                                      Container(
                                        width: 8,
                                        height: 8,
                                        decoration: BoxDecoration(
                                          color: dotColor,
                                          shape: BoxShape.circle,
                                        ),
                                      ),
                                      const SizedBox(width: 4),
                                    ],
                                    Text(
                                      Localization.translate(colorName, lang),
                                      style: const TextStyle(
                                        fontFamily: 'Cairo',
                                        fontSize: 11,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 4.0),
                          child: Row(
                            children: [
                              if ((item['code'] ?? '').toString().isNotEmpty)
                                Text(
                                  '${item['code']} • ',
                                  style: TextStyle(
                                    fontSize: 11,
                                    color: Colors.grey.shade600,
                                  ),
                                ),
                              Text(
                                price > 0
                                    ? '${price.toStringAsFixed(2)} ${Localization.translate('دج', lang)}'
                                    : Localization.translate('السعر: --', lang),
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: price > 0
                                      ? const Color(0xFF10B981)
                                      : Colors.grey.shade500,
                                ),
                              ),
                            ],
                          ),
                        ),
                        trailing: IconButton(
                          icon: Icon(Icons.add_circle, color: _blue, size: 28),
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
    );
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;

    // إذا كانت النافذة مدمجة داخل النافذة العائمة القابلة للتحريك
    if (widget.isEmbedded) {
      return Directionality(
        textDirection: TextDirection.rtl,
        child: Material(
          color: Theme.of(context).scaffoldBackgroundColor,
          child: _buildContent(context, lang),
        ),
      );
    }

    // إذا كانت شاشة كاملة
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
            title: Text(
              Localization.translate('المستودع (إضافة للفاتورة)', lang),
              style: const TextStyle(
                fontFamily: 'Cairo',
                color: Colors.white,
                fontSize: 17,
                fontWeight: FontWeight.bold,
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
          body: _buildContent(context, lang),
        ),
      ),
    );
  }
}
