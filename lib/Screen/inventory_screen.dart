import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../services/cloud_sync_service.dart';
import '../sql_database.dart';
import 'inventory_item_history_screen.dart';
import 'inventory_adjustment_screen.dart';
import 'material_remnants_screen.dart';

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
  StreamSubscription? _syncSub;

  // Colors
  static const _blue = Color(0xFF2563EB);
  static const _cyan = Color(0xFF0EA5E9);
  Color get _bg => Theme.of(context).scaffoldBackgroundColor;
  Color get _cardBg => Theme.of(context).cardColor;
  Color get _text => Theme.of(context).colorScheme.onSurface;
  Color get _textDim =>
      Theme.of(context).colorScheme.onSurface.withOpacity(0.7);
  Color get _divider => Theme.of(context).dividerColor;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.isManager && !settings.canAccessInventory()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _loadLocations();
    _syncSub = CloudSyncService().dbUpdateStream.listen((_) {
      if (mounted) {
        _loadLocations(preferredLocationId: _selectedLocationId);
      }
    });
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadLocations({int? preferredLocationId}) async {
    final locs = await widget.db.readLocations();
    if (mounted) {
      setState(() {
        _locations = locs;
        if (_locations.isNotEmpty) {
          final preferredExists =
              preferredLocationId != null &&
              _locations.any(
                (location) =>
                    (location['id'] as num?)?.toInt() == preferredLocationId,
              );
          _selectedLocationId = preferredExists
              ? preferredLocationId
              : (_locations.first['id'] as num).toInt();
          final selectedLocation = _locations.firstWhere(
            (location) =>
                (location['id'] as num?)?.toInt() == _selectedLocationId,
            orElse: () => _locations.first,
          );
          final firstLocName =
              selectedLocation['name']?.toString() ?? 'المستودع الرئيسي';
          _selectedLocationName = firstLocName == 'المستودع الرئيسي'
              ? Localization.translate(
                  'المستودع الرئيسي',
                  Provider.of<AppSettingsProvider>(
                    context,
                    listen: false,
                  ).language,
                )
              : firstLocName;
          _loadStockData();
        } else {
          _isLoading = false;
        }
      });
    }
  }

  Future<void> _showAddLocationDialog() async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final lang = settings.language;
    if (!settings.canAddWarehouses()) return;

    final controller = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(Localization.translate('إضافة مستودع', lang)),
        content: TextField(
          controller: controller,
          autofocus: true,
          textInputAction: TextInputAction.done,
          decoration: InputDecoration(
            labelText: Localization.translate('اسم المستودع', lang),
            hintText: Localization.translate(
              'مثال: مستودع المواد الجاهزة',
              lang,
            ),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(Localization.translate('إلغاء', lang)),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(Localization.translate('إضافة', lang)),
          ),
        ],
      ),
    );
    controller.dispose();

    final cleanName = name?.trim() ?? '';
    if (!mounted || cleanName.isEmpty) return;
    final locationId = await widget.db.insertLocation(cleanName);
    if (!mounted || locationId == 0) return;
    await _loadLocations(preferredLocationId: locationId);
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
      if (itemType == 'Sections' ||
          itemType == 'Section' ||
          itemType == 'Profile') {
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
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final canAddLocation = settings.canAddWarehouses();

    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        backgroundColor: _bg,
        body: CustomScrollView(
          slivers: [
            _buildAppBar(lang),
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildLocationDropdown()),
                        if (canAddLocation) ...[
                          const SizedBox(width: 8),
                          IconButton.filled(
                            onPressed: _showAddLocationDialog,
                            icon: const Icon(Icons.add_business_rounded),
                            tooltip: Localization.translate(
                              'إضافة مستودع',
                              lang,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 16),
                    Row(
                      children: [
                        Expanded(
                          child: ChoiceChip(
                            label: Text(
                              Localization.translate('المتوفر فقط', lang),
                            ),
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
                            label: Text(
                              Localization.translate('كل العناصر', lang),
                            ),
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
                    _buildTotalValueCard(lang),
                    const SizedBox(height: 16),
                    TextField(
                      controller: _searchCtrl,
                      onChanged: (value) => _filterStock(),
                      decoration: InputDecoration(
                        hintText: Localization.translate(
                          'البحث عن عنصر، مقطع، لون...',
                          lang,
                        ),
                        prefixIcon: Icon(Icons.search, color: _blue),
                        filled: true,
                        fillColor: Theme.of(context).cardColor,
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
                    _buildStockList(lang),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppBar(AppLanguage lang) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final canAdjustInventory = settings.canAdjustInventory();
    return SliverAppBar(
      expandedHeight: 150.0,
      pinned: true,
      backgroundColor: Theme.of(context).cardColor,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(
                Icons.arrow_back_ios_rounded,
                color: Colors.white,
              ),
              onPressed: () => Navigator.pop(context),
            )
          : null,
      actions: [
        IconButton(
          icon: const Icon(Icons.refresh, color: Colors.white),
          tooltip: Localization.translate('تحديث', lang),
          onPressed: () async {
            await CloudSyncService().syncPendingNow();
            _loadLocations(preferredLocationId: _selectedLocationId);
          },
        ),
        IconButton(
          icon: const Icon(Icons.recycling, color: Colors.white),
          tooltip: Localization.translate('الفضلات المتاحة', lang),
          onPressed: () => _showAvailableRemnantsDialog(lang),
        ),
        if (canAdjustInventory)
          IconButton(
            icon: const Icon(Icons.delete_sweep, color: Colors.redAccent),
            tooltip: Localization.translate(
              'تصفير المخزون (فترة تجريبية)',
              lang,
            ),
            onPressed: () {
              if (_selectedLocationId != null) {
                showDialog(
                  context: context,
                  builder: (ctx) => AlertDialog(
                    title: Row(
                      children: [
                        const Icon(Icons.warning, color: Colors.red),
                        const SizedBox(width: 8),
                        Text(Localization.translate('تصفير المخزون!', lang)),
                      ],
                    ),
                    content: Text(
                      Localization.translate(
                        'هل أنت متأكد أنك تريد تصفير المخزون بالكامل وجعل كل الكميات 0؟\n\nلا يمكن التراجع عن هذا الإجراء!',
                        lang,
                      ),
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(ctx),
                        child: Text(Localization.translate('إلغاء', lang)),
                      ),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red,
                        ),
                        onPressed: () async {
                          Navigator.pop(ctx);
                          await widget.db.emptyInventory(_selectedLocationId!);
                          await _loadStockData();
                          if (mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(
                                  Localization.translate(
                                    'تم تصفير المخزون بنجاح',
                                    lang,
                                  ),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                                backgroundColor: Colors.green,
                              ),
                            );
                          }
                        },
                        child: Text(
                          Localization.translate('تأكيد التصفير', lang),
                          style: const TextStyle(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              }
            },
          ),
        IconButton(
          icon: const Icon(Icons.recycling_rounded, color: Colors.white),
          tooltip: lang == AppLanguage.arabic
              ? 'إدارة فضلات الألواح والمقاطع (Chutes)'
              : 'Gestion des chutes (Panneaux & Profilés)',
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => const MaterialRemnantsScreen(),
              ),
            );
          },
        ),
        if (canAdjustInventory)
          IconButton(
            icon: const Icon(Icons.inventory, color: Colors.white),
            tooltip: Localization.translate('جرد سنوي / تعديل المخزون', lang),
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
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: Theme.of(context).brightness == Brightness.dark
                  ? [Color(0xFF111827), Color(0xFF070E1D)]
                  : [_blue, _cyan],
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
        title: Text(
          Localization.translate('جرد المخزون', lang),
          style: const TextStyle(
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

  Widget _buildTotalValueCard(AppLanguage lang) {
    if (_isLoading) return const SizedBox.shrink();

    String formattedTotal = _totalValue.toStringAsFixed(2);
    if (_totalValue == _totalValue.truncateToDouble()) {
      formattedTotal = _totalValue.toInt().toString();
    }

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: Theme.of(context).brightness == Brightness.dark
              ? [Color(0xFF111827), Color(0xFF070E1D)]
              : [_blue, _cyan],
        ),
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
          Row(
            children: [
              const Icon(
                Icons.account_balance_wallet_rounded,
                color: Colors.white,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                Localization.translate('القيمة الإجمالية للمخزون', lang),
                style: const TextStyle(
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
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 4),
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
          icon: Icon(Icons.keyboard_arrow_down_rounded, color: _textDim),
          items: _locations.map((loc) {
            final locName = loc['name']?.toString() ?? 'المستودع الرئيسي';
            final displayName = locName == 'المستودع الرئيسي'
                ? Localization.translate(
                    'المستودع الرئيسي',
                    Provider.of<AppSettingsProvider>(
                      context,
                      listen: false,
                    ).language,
                  )
                : locName;
            return DropdownMenuItem<int>(
              value: (loc['id'] as num).toInt(),
              child: Row(
                children: [
                  const Icon(Icons.storefront_rounded, color: _blue, size: 20),
                  const SizedBox(width: 12),
                  Text(
                    displayName,
                    style: TextStyle(
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
                final matchedLocName =
                    _locations
                        .firstWhere((l) => l['id'] == val)['name']
                        ?.toString() ??
                    'المستودع الرئيسي';
                _selectedLocationName = matchedLocName == 'المستودع الرئيسي'
                    ? Localization.translate(
                        'المستودع الرئيسي',
                        Provider.of<AppSettingsProvider>(
                          context,
                          listen: false,
                        ).language,
                      )
                    : matchedLocName;
              });
              _loadStockData();
            }
          },
        ),
      ),
    );
  }

  Widget _buildStockList(AppLanguage lang) {
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
            Text(
              Localization.translate('لا توجد عناصر في هذا المخزون', lang),
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
        final minQty = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
        final alertEnabled =
            ((item['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1;
        final bool isLowStock =
            alertEnabled && minQty > 0 && quantity <= minQty;

        return Container(
          margin: EdgeInsets.only(bottom: 12),
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
                            style: TextStyle(
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
                                Localization.translate(itemType, lang),
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 12,
                                  color: _textDim,
                                ),
                              ),
                              if (colorName.isNotEmpty) ...[
                                const SizedBox(width: 8),
                                Icon(Icons.circle, size: 4, color: _divider),
                                const SizedBox(width: 8),
                                Text(
                                  Localization.translate(colorName, lang),
                                  style: TextStyle(
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
                        Text(
                          Localization.translate('الرصيد', lang),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            color: _textDim,
                          ),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            if (isLowStock) ...[
                              Icon(
                                Icons.warning_amber_rounded,
                                color: Colors.orange.shade800,
                                size: 16,
                              ),
                              const SizedBox(width: 4),
                            ],
                            Text(
                              quantity.toStringAsFixed(
                                quantity.truncateToDouble() == quantity ? 0 : 2,
                              ),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.w900,
                                fontSize: 18,
                                color: quantity > 0
                                    ? (isLowStock
                                          ? Colors.orange.shade800
                                          : _text)
                                    : Colors.red,
                              ),
                            ),
                          ],
                        ),
                        if (alertEnabled && minQty > 0)
                          Text(
                            '${Localization.translate('الحد الأدنى', lang)}: ${minQty.toStringAsFixed(minQty.truncateToDouble() == minQty ? 0 : 2)}',
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 9,
                              color: isLowStock
                                  ? Colors.orange.shade800
                                  : _textDim,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: Icon(
                        alertEnabled
                            ? Icons.notifications_active_rounded
                            : Icons.notifications_none_rounded,
                        size: 20,
                        color: alertEnabled
                            ? (isLowStock ? Colors.orange.shade800 : _blue)
                            : _textDim,
                      ),
                      onPressed: () => _showMinQtyDialog(item),
                      tooltip: Localization.translate(
                        'تنبيه الحد الأدنى',
                        lang,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Icon(
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

  Future<void> _showMinQtyDialog(Map<String, dynamic> item) async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final itemId = item['item_id'] as int;
    final itemType = item['item_type'] as String;
    final itemName = item['item_name'] as String;
    final colorId = item['color_id'] as int?;
    final minQty = (item['min_qty'] as num?)?.toDouble() ?? 0.0;
    bool alertEnabled =
        ((item['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1;

    final controller = TextEditingController(
      text: minQty.toStringAsFixed(minQty.truncateToDouble() == minQty ? 0 : 2),
    );

    await showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => Directionality(
          textDirection: TextDirection.rtl,
          child: AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            title: Row(
              children: [
                const Icon(Icons.notifications_active_outlined, color: _blue),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    Localization.translate('تنبيه الحد الأدنى للمخزون', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                ),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  itemName,
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(
                    labelText: Localization.translate(
                      'أقل كمية مقبولة للتنبيه',
                      lang,
                    ),
                    labelStyle: const TextStyle(fontFamily: 'Cairo'),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                SwitchListTile(
                  contentPadding: EdgeInsets.zero,
                  value: alertEnabled,
                  onChanged: (value) =>
                      setDialogState(() => alertEnabled = value),
                  title: Text(
                    Localization.translate('تفعيل تنبيه نفاد الكمية', lang),
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  subtitle: Text(
                    Localization.translate(
                      'لن يظهر هذا العنصر في التنبيهات إلا إذا كان هذا الخيار مفعلاً.',
                      lang,
                    ),
                    style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  ),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: Text(
                  Localization.translate('إلغاء', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.grey,
                  ),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: _blue,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () async {
                  final double? val = double.tryParse(controller.text.trim());
                  if (val != null && val >= 0) {
                    await widget.db.updateMinQty(
                      itemType: itemType,
                      itemId: itemId,
                      colorId: colorId,
                      locationId: _selectedLocationId!,
                      minQty: val,
                      alertEnabled: alertEnabled,
                    );
                    if (context.mounted) {
                      Navigator.pop(context);
                    }
                    _loadStockData();
                  }
                },
                child: Text(
                  Localization.translate('حفظ', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showAvailableRemnantsDialog(AppLanguage lang) async {
    final locationId = _selectedLocationId;
    if (locationId == null) return;
    final remnants = List<Map<String, dynamic>>.from(
      await widget.db.readAllAvailableMaterialRemnants(
      locationId: locationId,
      ),
    );
    if (!mounted) return;
    await showDialog(
      context: context,
      builder: (context) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          title: Row(
            children: [
              const Icon(Icons.recycling, color: Colors.teal),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  Localization.translate('الفضلات المتاحة', lang),
                  style: const TextStyle(
                    fontFamily: 'Cairo',
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
          content: StatefulBuilder(
            builder: (dialogContext, setDialogState) => SizedBox(
              width: 560,
              child: remnants.isEmpty
                  ? Text(
                      Localization.translate(
                        'لا توجد فضلات قابلة للاستعمال في هذا المخزون.',
                        lang,
                      ),
                      style: const TextStyle(fontFamily: 'Cairo'),
                    )
                  : ListView.separated(
                      shrinkWrap: true,
                      itemCount: remnants.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (context, index) {
                        final row = remnants[index];
                        final length =
                            ((row['length_mm'] as num?)?.toDouble() ?? 0).round();
                        final name = row['item_name']?.toString() ?? '';
                        final code = row['item_code']?.toString() ?? '';
                        final color = row['color_name']?.toString() ?? '';
                        final series = row['series_name']?.toString() ?? '';
                        final address =
                            [row['rack_code'], row['shelf_code'], row['bin_code']]
                                .map((value) => value?.toString().trim() ?? '')
                                .where((value) => value.isNotEmpty)
                                .join(' / ');
                        return ListTile(
                          dense: true,
                          leading: const Icon(Icons.straighten, color: _blue),
                          title: Text(
                            '${row['ticket_code']} - ${code.isEmpty ? name : '[$code] $name'}',
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          subtitle: Text(
                            [
                              if (series.isNotEmpty) series,
                              if (color.isNotEmpty) color,
                              if (address.isNotEmpty) address,
                            ].join(' - '),
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                          trailing: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '$length ${Localization.translate('مم', lang)}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontWeight: FontWeight.bold,
                                  color: Colors.teal,
                                ),
                              ),
                              IconButton(
                                tooltip: Localization.translate('تسجيل هدر', lang),
                                icon: const Icon(
                                  Icons.delete_outline,
                                  color: Colors.redAccent,
                                ),
                                onPressed: () async {
                                  final confirmed = await showDialog<bool>(
                                    context: dialogContext,
                                    builder: (confirmContext) => AlertDialog(
                                      title: Text(
                                        Localization.translate('تسجيل هدر', lang),
                                      ),
                                      content: Text(
                                        Localization.translate(
                                          'سيتم حفظ الفضلة كسجل هدر مع إبقاء رقمها وأثرها، ولن تُحذف نهائيًا. هل تريد المتابعة؟',
                                          lang,
                                        ),
                                      ),
                                      actions: [
                                        TextButton(
                                          onPressed: () => Navigator.pop(confirmContext, false),
                                          child: Text(Localization.translate('إلغاء', lang)),
                                        ),
                                        FilledButton(
                                          onPressed: () => Navigator.pop(confirmContext, true),
                                          child: Text(Localization.translate('تأكيد', lang)),
                                        ),
                                      ],
                                    ),
                                  );
                                  if (confirmed != true) return;
                                  final result = await widget.db.markMaterialRemnantAsScrap(
                                    remnantId: (row['id'] as num).toInt(),
                                    note: 'هدر يدوي من شاشة المخزون',
                                  );
                                  if (result['marked'] == true) {
                                    setDialogState(() => remnants.removeAt(index));
                                  }
                                },
                              ),
                            ],
                          ),
                        );
                      },
                    ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: Text(Localization.translate('إغلاق', lang)),
            ),
          ],
        ),
      ),
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
