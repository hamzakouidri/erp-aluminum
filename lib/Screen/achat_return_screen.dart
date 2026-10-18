import 'package:database_data/widgets/app_material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:database_data/settings/localization.dart';
import '../sql_database.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:provider/provider.dart';

class AchatReturnScreen extends StatefulWidget {
  final SqlDatabase db;
  final bool? isWorkshop;

  const AchatReturnScreen({super.key, required this.db, this.isWorkshop});

  @override
  State<AchatReturnScreen> createState() => _AchatReturnScreenState();
}

class _AchatReturnScreenState extends State<AchatReturnScreen> {
  List<Map<String, dynamic>> _suppliers = [];
  int? _selectedSupplierId;
  List<Map<String, dynamic>> _purchasedItems = [];
  Map<int, double> _returnQuantities = {};
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSuppliers();
  }

  Future<void> _loadSuppliers() async {
    final suppliers = await widget.db.readSuppliers();
    setState(() {
      _suppliers = suppliers;
      _isLoading = false;
    });
  }

  Future<void> _loadItemsForSupplier(int supplierId) async {
    setState(() => _isLoading = true);

    // Find the supplier name from the loaded list
    String supplierName = '';
    try {
      supplierName = _suppliers.firstWhere(
        (s) => s['id'] == supplierId,
      )['name'];
    } catch (_) {}

    final achats = await widget.db.readAchatsBySupplierName(
      supplierName,
      isWorkshop: widget.isWorkshop,
    );

    List<Map<String, dynamic>> items = [];
    for (var achat in achats) {
      if (achat['status'] == 'Cancelled' ||
          achat['status'] == 'Returned' ||
          achat['status'] == 'ملغى')
        continue;
      final achatId = achat['id'] as int;
      final invoice = achat['invoice_number'] ?? '';

      final achatItems = await widget.db.readAchatItems(achatId);
      for (var item in achatItems) {
        double currentQty = (item['quantity'] as num).toDouble();
        if (currentQty > 0) {
          items.add({...item, 'invoice_number': invoice, 'achat_id': achatId});
        }
      }
    }

    setState(() {
      _purchasedItems = items;
      _returnQuantities.clear();
      _isLoading = false;
    });
  }

  void _confirmReturn() async {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;

    List<Map<String, dynamic>> itemsToReturn = [];
    Map<int, List<Map<String, dynamic>>> itemsByAchat = {};
    double totalRefund = 0.0;

    for (var item in _purchasedItems) {
      int id = item['id'];
      double returnQty = _returnQuantities[id] ?? 0.0;
      if (returnQty > 0) {
        int achatId = item['achat_id'];
        double price = (item['price'] as num).toDouble();

        var returnItem = {
          'id': id,
          'returnQty': returnQty,
          'currentQty': item['quantity'],
          'refundAmount': returnQty * price,
        };

        if (!itemsByAchat.containsKey(achatId)) {
          itemsByAchat[achatId] = [];
        }
        itemsByAchat[achatId]!.add(returnItem);
        totalRefund += (returnQty * price);
      }
    }

    if (itemsByAchat.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('الرجاء تحديد كميات للإرجاع', lang),
          ),
        ),
      );
      return;
    }

    bool confirm =
        await showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(
              Localization.translate('تأكيد الإرجاع', lang),
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            content: Text(
              '${Localization.translate('هل أنت متأكد من إرجاع هذه العناصر؟', lang)}\n'
              '${Localization.translate('إجمالي المبلغ المسترد:', lang)} ${NumberFormat('#,##0.00').format(totalRefund)} دج',
              style: TextStyle(fontFamily: 'Cairo'),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(
                  Localization.translate('إلغاء', lang),
                  style: TextStyle(fontFamily: 'Cairo'),
                ),
              ),
              ElevatedButton(
                onPressed: () => Navigator.pop(ctx, true),
                style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
                child: Text(
                  Localization.translate('تأكيد', lang),
                  style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    for (var entry in itemsByAchat.entries) {
      int achatId = entry.key;
      List<Map<String, dynamic>> returns = entry.value;
      double achatRefund = returns.fold(
        0.0,
        (sum, i) => sum + (i['refundAmount'] as double),
      );
      try {
        await widget.db.returnAchatInvoice(achatId, returns, achatRefund);
      } catch (error) {
        // Each invoice is returned atomically; earlier invoices stay done.
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$error'), backgroundColor: Colors.red),
        );
        _loadItemsForSupplier(_selectedSupplierId!);
        return;
      }
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            Localization.translate('تم معالجة المردودات بنجاح', lang),
          ),
        ),
      );
      _loadItemsForSupplier(_selectedSupplierId!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final currencyFormat = NumberFormat('#,##0.00', 'en_US');

    return Directionality(
      textDirection: lang == AppLanguage.arabic
          ? TextDirection.rtl
          : TextDirection.ltr,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            Localization.translate('مردودات المشتريات (Retours)', lang),
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          backgroundColor: Colors.blue.shade600,
          foregroundColor: Colors.white,
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: DropdownButtonFormField<int>(
                      decoration: InputDecoration(
                        labelText: Localization.translate('اختر المورد', lang),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                        filled: true,
                        fillColor: Colors.white,
                      ),
                      initialValue: _selectedSupplierId,
                      items: _suppliers.map((s) {
                        return DropdownMenuItem<int>(
                          value: s['id'] as int,
                          child: Text(
                            s['name'] ?? '',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() => _selectedSupplierId = val);
                          _loadItemsForSupplier(val);
                        }
                      },
                    ),
                  ),
                  if (_selectedSupplierId != null && _purchasedItems.isEmpty)
                    Expanded(
                      child: Center(
                        child: Text(
                          Localization.translate(
                            'لا توجد مشتريات متاحة للإرجاع من هذا المورد',
                            lang,
                          ),
                          style: TextStyle(fontFamily: 'Cairo', fontSize: 16),
                        ),
                      ),
                    ),
                  if (_purchasedItems.isNotEmpty)
                    Expanded(
                      child: ListView.builder(
                        itemCount: _purchasedItems.length,
                        itemBuilder: (context, index) {
                          final item = _purchasedItems[index];
                          final id = item['id'] as int;
                          final name = item['item_name'] ?? '';
                          final invoice = item['invoice_number'] ?? '';
                          final price = (item['price'] as num).toDouble();
                          final currentQty = (item['quantity'] as num)
                              .toDouble();
                          final returnQty = _returnQuantities[id] ?? 0.0;

                          return Card(
                            margin: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 6,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.all(12.0),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          Localization.translate(name, lang),
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        '${Localization.translate('فاتورة: ', lang)}$invoice',
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          color: Colors.blue.shade700,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 8),
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Text(
                                        '${Localization.translate('الكمية المتاحة: ', lang)}$currentQty',
                                        style: TextStyle(fontFamily: 'Cairo'),
                                      ),
                                      Text(
                                        '${Localization.translate('السعر: ', lang)}${currencyFormat.format(price)} ${Localization.translate('دج', lang)}',
                                        style: TextStyle(fontFamily: 'Cairo'),
                                      ),
                                    ],
                                  ),
                                  SizedBox(height: 12),
                                  Row(
                                    children: [
                                      Text(
                                        Localization.translate('المراد إرجاعه: ', lang),
                                        style: TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.remove_circle,
                                          color: Colors.red,
                                        ),
                                        onPressed: () {
                                          if (returnQty > 0) {
                                            setState(() {
                                              _returnQuantities[id] =
                                                  returnQty - 1;
                                            });
                                          }
                                        },
                                      ),
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                          horizontal: 16,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          border: Border.all(
                                            color: Colors.grey,
                                          ),
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Text(
                                          returnQty.toString(),
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                      IconButton(
                                        icon: Icon(
                                          Icons.add_circle,
                                          color: Colors.green,
                                        ),
                                        onPressed: () {
                                          if (returnQty < currentQty) {
                                            setState(() {
                                              _returnQuantities[id] =
                                                  returnQty + 1;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                ],
              ),
        bottomNavigationBar: _purchasedItems.isEmpty
            ? null
            : Container(
                padding: EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 10)],
                ),
                child: ElevatedButton.icon(
                  onPressed: _confirmReturn,
                  icon: Icon(Icons.assignment_return),
                  label: Text(
                    Localization.translate('تأكيد الإرجاع', lang),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange.shade600,
                    foregroundColor: Colors.white,
                    padding: EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
      ),
    );
  }
}
