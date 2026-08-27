import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class InventoryAdjustmentScreen extends StatefulWidget {
  final SqlDatabase db;
  final int locationId;
  final String locationName;

  const InventoryAdjustmentScreen({
    super.key,
    required this.db,
    required this.locationId,
    required this.locationName,
  });

  @override
  State<InventoryAdjustmentScreen> createState() =>
      _InventoryAdjustmentScreenState();
}

class _InventoryAdjustmentScreenState extends State<InventoryAdjustmentScreen> {
  List<Map<String, dynamic>> _stockData = [];
  List<Map<String, dynamic>> _filteredStockData = [];
  final Map<int, TextEditingController> _controllers = {};
  final Map<int, TextEditingController> _minQtyControllers = {};
  final TextEditingController _searchCtrl = TextEditingController();
  bool _isLoading = true;

  bool get _canAdjust => Provider.of<AppSettingsProvider>(
    context,
    listen: false,
  ).canAdjustInventory();

  @override
  void initState() {
    super.initState();
    _loadStockData();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = Provider.of<AppSettingsProvider>(context);
    if (!settings.canAdjustInventory()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      });
    }
  }

  Future<void> _loadStockData() async {
    setState(() => _isLoading = true);
    final data = await widget.db.readCurrentStock(widget.locationId);

    // Sort data alphabetically
    data.sort(
      (a, b) => (a['item_name']?.toString() ?? '').compareTo(
        b['item_name']?.toString() ?? '',
      ),
    );

    setState(() {
      _stockData = data;
      _filteredStockData = data;
      for (int i = 0; i < data.length; i++) {
        _controllers[i] = TextEditingController(
          text: (data[i]['quantity'] as num).toDouble().toStringAsFixed(
            (data[i]['quantity'] as num).toDouble().truncateToDouble() ==
                    (data[i]['quantity'] as num).toDouble()
                ? 0
                : 2,
          ),
        );
        _minQtyControllers[i] = TextEditingController(
          text: ((data[i]['min_qty'] ?? 0.0) as num).toDouble().toStringAsFixed(
            ((data[i]['min_qty'] ?? 0.0) as num)
                        .toDouble()
                        .truncateToDouble() ==
                    ((data[i]['min_qty'] ?? 0.0) as num).toDouble()
                ? 0
                : 2,
          ),
        );
      }
      _isLoading = false;
    });
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
          return name.contains(query) || type.contains(query);
        }).toList();
      }
    });
  }

  Future<void> _saveAdjustments() async {
    if (!_canAdjust) return;
    setState(() => _isLoading = true);

    // Find all changed quantities
    for (int i = 0; i < _filteredStockData.length; i++) {
      final item = _filteredStockData[i];
      final originalIndex = _stockData.indexOf(item);

      // 1. Quantity change
      final newQuantity =
          double.tryParse(_controllers[originalIndex]?.text ?? '') ?? 0.0;
      final oldQuantity = (item['quantity'] as num).toDouble();

      if (newQuantity != oldQuantity) {
        final double difference = newQuantity - oldQuantity;

        await widget.db.updateInventory(
          itemType: item['item_type'] as String,
          itemId: item['item_id'] as int,
          colorId: item['color_id'] as int?,
          quantityChange: difference,
          locationId: widget.locationId,
          transactionType: 'Adjustment',
          referenceId: 0,
        );
      }

      // 2. Minimum Quantity change
      final newMinQty =
          double.tryParse(_minQtyControllers[originalIndex]?.text ?? '') ?? 0.0;
      final oldMinQty = ((item['min_qty'] ?? 0.0) as num).toDouble();

      if (newMinQty != oldMinQty) {
        await widget.db.updateMinQty(
          itemType: item['item_type'] as String,
          itemId: item['item_id'] as int,
          colorId: item['color_id'] as int?,
          locationId: widget.locationId,
          minQty: newMinQty,
          alertEnabled:
              ((item['low_stock_alert_enabled'] as num?)?.toInt() ?? 0) == 1,
        );
      }
    }

    if (mounted) {
      final lang = Provider.of<AppSettingsProvider>(
        context,
        listen: false,
      ).language;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('تم حفظ تسوية المخزون بنجاح!', lang),
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final settings = Provider.of<AppSettingsProvider>(context);
    return Directionality(
      textDirection: TextDirection.rtl,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            "${Localization.translate('جرد المخزون: ', lang)}${widget.locationName}",
            style: const TextStyle(fontFamily: 'Cairo'),
          ),
          actions: [
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: settings.canAdjustInventory()
                  ? _saveAdjustments
                  : null,
              tooltip: Localization.translate('حفظ التعديلات', lang),
            ),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: TextField(
                      controller: _searchCtrl,
                      onChanged: (_) => _filterStock(),
                      decoration: InputDecoration(
                        hintText: Localization.translate(
                          'البحث عن عنصر، مقطع، لون...',
                          lang,
                        ),
                        prefixIcon: const Icon(Icons.search),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  Expanded(
                    child: ListView.builder(
                      itemCount: _filteredStockData.length,
                      itemBuilder: (context, index) {
                        final item = _filteredStockData[index];
                        final originalIndex = _stockData.indexOf(item);
                        final itemType = item['item_type'] as String;
                        final colorName = item['color_name'] as String?;
                        return Card(
                          margin: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 4,
                          ),
                          child: ListTile(
                            title: Text(
                              item['item_name'].toString(),
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            subtitle: Text(
                              "${Localization.translate(itemType, lang)}${colorName != null && colorName.isNotEmpty ? ' - ${Localization.translate(colorName, lang)}' : ''}",
                            ),
                            trailing: SizedBox(
                              width: 220,
                              child: Row(
                                children: [
                                  Expanded(
                                    child: TextField(
                                      controller: _controllers[originalIndex],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'الكمية',
                                          lang,
                                        ),
                                        labelStyle: const TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'Cairo',
                                        ),
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: TextField(
                                      controller:
                                          _minQtyControllers[originalIndex],
                                      keyboardType: TextInputType.number,
                                      textAlign: TextAlign.center,
                                      decoration: InputDecoration(
                                        labelText: Localization.translate(
                                          'الحد الأدنى',
                                          lang,
                                        ),
                                        labelStyle: const TextStyle(
                                          fontSize: 10,
                                          fontFamily: 'Cairo',
                                        ),
                                        border: const OutlineInputBorder(),
                                        contentPadding:
                                            const EdgeInsets.symmetric(
                                              vertical: 8,
                                            ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
