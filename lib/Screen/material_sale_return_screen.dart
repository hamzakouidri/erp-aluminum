import 'package:database_data/widgets/app_material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';

class MaterialSaleReturnScreen extends StatefulWidget {
  final SqlDatabase db;

  const MaterialSaleReturnScreen({super.key, required this.db});

  @override
  State<MaterialSaleReturnScreen> createState() =>
      _MaterialSaleReturnScreenState();
}

class _MaterialSaleReturnScreenState extends State<MaterialSaleReturnScreen> {
  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> _items = [];
  final Map<String, double> _quantities = {};
  int? _saleId;
  bool _loading = true;
  bool _saving = false;

  String _t(String key) => Localization.translate(
        key,
        context.read<AppSettingsProvider>().language,
      );

  String _key(Map<String, dynamic> row) =>
      '${row['item_type']}|${row['item_id']}|${row['item_code']}|${row['color_id']}';

  @override
  void initState() {
    super.initState();
    _loadSales();
  }

  Future<void> _loadSales() async {
    final rows = await widget.db.readMaterialSales();
    if (!mounted) return;
    setState(() {
      _sales = rows.where((row) {
        final type = row['doc_type']?.toString();
        final status = row['status']?.toString().toLowerCase();
        final deducted = (row['stock_deducted'] as num?)?.toInt() == 1;
        final internal = (row['is_internal'] as num?)?.toInt() == 1;
        return type != 'retour' && status != 'returned' && deducted && !internal;
      }).toList();
      _loading = false;
    });
  }

  Future<void> _selectSale(int? id) async {
    setState(() {
      _saleId = id;
      _items = [];
      _quantities.clear();
      _loading = id != null;
    });
    if (id == null) return;
    final rows = await widget.db.readReturnableMaterialSaleItems(id);
    if (!mounted) return;
    setState(() {
      _items = rows;
      _loading = false;
    });
  }

  Future<void> _submit() async {
    final selected = _items
        .where((row) => (_quantities[_key(row)] ?? 0) > 0)
        .map((row) => {...row, 'quantity': _quantities[_key(row)]})
        .toList();
    if (selected.isEmpty || _saleId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('الرجاء تحديد كميات للإرجاع'))),
      );
      return;
    }
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(_t('تأكيد الإرجاع')),
        content: Text(_t('هل أنت متأكد من إرجاع هذه العناصر؟')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('إلغاء')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد الإرجاع')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    setState(() => _saving = true);
    try {
      await widget.db.returnMaterialSaleItems(_saleId!, selected);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_t('تم معالجة المردودات بنجاح'))),
      );
      await _selectSale(_saleId);
      await _loadSales();
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${_t('خطأ')}: $error'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final money = NumberFormat('#,##0.00');
    return Scaffold(
      appBar: AppBar(title: Text(_t('إرجاع من الزبون إلى المخزون'))),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<int>(
              initialValue: _saleId,
              decoration: InputDecoration(
                labelText: _t('اختر وثيقة البيع'),
                border: const OutlineInputBorder(),
              ),
              items: _sales.map((sale) => DropdownMenuItem<int>(
                    value: (sale['id'] as num).toInt(),
                    child: Text(
                      '${sale['sale_code']} • ${sale['client_name']}',
                      overflow: TextOverflow.ellipsis,
                    ),
                  )).toList(),
              onChanged: _selectSale,
            ),
          ),
          if (_loading)
            const Expanded(child: Center(child: CircularProgressIndicator()))
          else if (_saleId != null && _items.isEmpty)
            Expanded(child: Center(child: Text(_t('لا توجد عناصر للإرجاع'))))
          else
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                itemCount: _items.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final item = _items[index];
                  final key = _key(item);
                  final maximum =
                      (item['returnable_quantity'] as num?)?.toDouble() ?? 0;
                  final quantity = _quantities[key] ?? 0;
                  return Card(
                    child: ListTile(
                      title: Text(item['item_name']?.toString() ?? '—'),
                      subtitle: Text(
                        '${_t('الكمية المتاحة: ')}${money.format(maximum)} • '
                        '${_t('السعر: ')}${money.format(item['unit_price'] ?? 0)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            onPressed: quantity <= 0
                                ? null
                                : () => setState(() =>
                                    _quantities[key] = (quantity - 1)
                                        .clamp(0.0, maximum)
                                        .toDouble()),
                            icon: const Icon(Icons.remove_circle_outline),
                          ),
                          SizedBox(
                            width: 58,
                            child: Text(
                              money.format(quantity),
                              textAlign: TextAlign.center,
                              style: const TextStyle(fontWeight: FontWeight.bold),
                            ),
                          ),
                          IconButton(
                            onPressed: quantity >= maximum
                                ? null
                                : () => setState(() =>
                                    _quantities[key] = (quantity + 1)
                                        .clamp(0.0, maximum)
                                        .toDouble()),
                            icon: const Icon(Icons.add_circle_outline),
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
      bottomNavigationBar: _saleId == null
          ? null
          : SafeArea(
              minimum: const EdgeInsets.all(16),
              child: FilledButton.icon(
                onPressed: _saving ? null : _submit,
                icon: const Icon(Icons.assignment_return_rounded),
                label: Text(_t('تأكيد الإرجاع')),
              ),
            ),
    );
  }
}
