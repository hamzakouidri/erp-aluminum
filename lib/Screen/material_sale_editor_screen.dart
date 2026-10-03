import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../services/material_sale_pdf_service.dart';

class MaterialSaleEditorScreen extends StatefulWidget {
  final SqlDatabase db;
  final int? saleId; // null = create new

  const MaterialSaleEditorScreen({super.key, required this.db, this.saleId});

  @override
  State<MaterialSaleEditorScreen> createState() =>
      _MaterialSaleEditorScreenState();
}

class _MaterialSaleEditorScreenState extends State<MaterialSaleEditorScreen> {
  static const _blue = Color(0xFF1E3A8A);
  static const _cyan = Color(0xFF06B6D4);
  static const _green = Color(0xFF10B981);
  static const _red = Color(0xFFEF4444);

  final _fmt = NumberFormat('#,##0.00');

  // ── Sale header fields ────────────────────────────────────────────────────
  String _saleCode = '';
  String _docType = 'bon_livraison';
  String _status = 'draft';
  int? _clientId;
  String _clientName = '';
  String _clientPhone = '';
  String _notes = '';
  DateTime _saleDate = DateTime.now();

  // Financials
  double _discountAmount = 0.0;
  double _paidAmount = 0.0;

  // ── Items ─────────────────────────────────────────────────────────────────
  final List<Map<String, dynamic>> _items = [];

  // ── Loading ───────────────────────────────────────────────────────────────
  bool _isLoading = false;
  bool _isSaving = false;

  // ── Controllers ───────────────────────────────────────────────────────────
  final _clientCtrl = TextEditingController();
  final _clientPhoneCtrl = TextEditingController();
  final _notesCtrl = TextEditingController();
  final _discountCtrl = TextEditingController(text: '0');
  final _paidCtrl = TextEditingController(text: '0');

  // ── Clients list ─────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _clients = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  @override
  void dispose() {
    _clientCtrl.dispose();
    _clientPhoneCtrl.dispose();
    _notesCtrl.dispose();
    _discountCtrl.dispose();
    _paidCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    setState(() => _isLoading = true);
    try {
      _clients = await widget.db.readClient();
      if (widget.saleId != null) {
        final sale = await widget.db.readMaterialSaleById(widget.saleId!);
        if (sale != null) {
          _saleCode = sale['sale_code'] ?? '';
          _docType = sale['doc_type'] ?? 'bon_livraison';
          _status = sale['status'] ?? 'draft';
          _clientId = sale['client_id'] as int?;
          _clientName = sale['client_name'] ?? '';
          _clientPhone = sale['client_phone'] ?? '';
          _notes = sale['notes'] ?? '';
          _discountAmount = (sale['discount_amount'] as num?)?.toDouble() ?? 0.0;
          _paidAmount = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
          final saleDateStr = sale['sale_date'] as String? ?? '';
          if (saleDateStr.isNotEmpty) {
            _saleDate = DateTime.tryParse(saleDateStr) ?? DateTime.now();
          }
          _clientCtrl.text = _clientName;
          _clientPhoneCtrl.text = _clientPhone;
          _notesCtrl.text = _notes;
          _discountCtrl.text = _discountAmount.toStringAsFixed(2);
          _paidCtrl.text = _paidAmount.toStringAsFixed(2);

          final items = await widget.db.readMaterialSaleItems(widget.saleId!);
          _items.addAll(items.map((i) => Map<String, dynamic>.from(i)));
        }
      } else {
        _saleCode = await widget.db.nextMaterialSaleCode();
      }
    } finally {
      setState(() => _isLoading = false);
    }
  }

  // ── Calculations ─────────────────────────────────────────────────────────
  double get _subtotal =>
      _items.fold(0.0, (s, i) => s + ((i['total_price'] as num?)?.toDouble() ?? 0.0));

  double get _netTotal => (_subtotal - _discountAmount).clamp(0.0, double.infinity);

  double get _remainingAmount => (_netTotal - _paidAmount).clamp(0.0, double.infinity);

  void _recalc() => setState(() {
        _discountAmount =
            double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
        _paidAmount =
            double.tryParse(_paidCtrl.text.replaceAll(',', '.')) ?? 0.0;
      });

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_clientName.trim().isEmpty) {
      _showSnack('يجب تحديد العميل / Client obligatoire', isError: true);
      return;
    }
    setState(() => _isSaving = true);
    try {
      final saleDateStr = _saleDate.toUtc().toIso8601String();

      if (widget.saleId == null) {
        // Create new
        final newId = await widget.db.insertMaterialSale(
          saleCode: _saleCode,
          clientId: _clientId,
          clientName: _clientName,
          clientPhone: _clientPhone,
          docType: _docType,
          status: _status,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
          remainingAmount: _remainingAmount,
          notes: _notes,
          saleDate: saleDateStr,
        );
        if (newId > 0) {
          await widget.db.saveMaterialSaleWithItems(
            saleId: newId,
            items: _items,
            subtotal: _subtotal,
            discountAmount: _discountAmount,
            netTotal: _netTotal,
            paidAmount: _paidAmount,
          );
          if (_status == 'confirmed' || _status == 'delivered') {
            await widget.db.deductStockForMaterialSale(newId);
          }
        }
      } else {
        // Update existing
        await widget.db.updateMaterialSale(
          widget.saleId!,
          clientId: _clientId,
          clientName: _clientName,
          clientPhone: _clientPhone,
          docType: _docType,
          status: _status,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
          remainingAmount: _remainingAmount,
          notes: _notes,
          saleDate: saleDateStr,
        );
        await widget.db.saveMaterialSaleWithItems(
          saleId: widget.saleId!,
          items: _items,
          subtotal: _subtotal,
          discountAmount: _discountAmount,
          netTotal: _netTotal,
          paidAmount: _paidAmount,
        );
        if (_status == 'confirmed' || _status == 'delivered') {
          await widget.db.deductStockForMaterialSale(widget.saleId!);
        }
      }

      CloudSyncService().notifyChange();
      if (mounted) {
        _showSnack('تم الحفظ / Enregistré ✔', isError: false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('خطأ في الحفظ: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _printDoc() async {
    if (widget.saleId == null && _items.isEmpty) {
      _showSnack('أضف عناصر أولاً / Ajoutez des articles', isError: true);
      return;
    }
    final sale = {
      'sale_code': _saleCode,
      'client_name': _clientName,
      'client_phone': _clientPhone,
      'doc_type': _docType,
      'status': _status,
      'subtotal': _subtotal,
      'discount_amount': _discountAmount,
      'net_total': _netTotal,
      'paid_amount': _paidAmount,
      'remaining_amount': _remainingAmount,
      'notes': _notes,
      'sale_date': _saleDate.toIso8601String(),
    };
    try {
      final bytes = await MaterialSalePdfService.generate(sale: sale, items: _items);
      await MaterialSalePdfService.printOrShare(bytes, _saleCode);
    } catch (e) {
      _showSnack('خطأ في الطباعة: $e', isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
      backgroundColor: isError ? _red : _green,
    ));
  }

  // ── Add item ──────────────────────────────────────────────────────────────
  void _openItemPicker() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItemPickerSheet(
        db: widget.db,
        onItemSelected: (item) {
          setState(() => _items.add(item));
        },
      ),
    );
  }

  // ── Remove item ───────────────────────────────────────────────────────────
  void _removeItem(int index) {
    setState(() => _items.removeAt(index));
  }

  // ── Edit item quantity/price inline ───────────────────────────────────────
  void _editItemDialog(int index) {
    final item = _items[index];
    final qtyCtrl = TextEditingController(
      text: (item['quantity'] as num?)?.toStringAsFixed(2) ?? '1',
    );
    final priceCtrl = TextEditingController(
      text: (item['unit_price'] as num?)?.toStringAsFixed(2) ?? '0',
    );
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          item['item_name'] ?? '',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantité / الكمية',
                labelStyle: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prix unitaire / السعر',
                labelStyle: TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () {
              final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
              setState(() {
                _items[index]['quantity'] = qty;
                _items[index]['unit_price'] = price;
                _items[index]['total_price'] = qty * price;
              });
              Navigator.pop(context);
            },
            child: const Text('حفظ', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ── Client picker dialog ───────────────────────────────────────────────────
  void _openClientPicker() {
    showDialog(
      context: context,
      builder: (_) {
        final search = TextEditingController();
        List<Map<String, dynamic>> filtered = List.from(_clients);
        return StatefulBuilder(builder: (ctx, setS) {
          return AlertDialog(
            title: const Text('اختر العميل / Choisir client',
                style: TextStyle(fontFamily: 'Cairo', fontSize: 14)),
            content: SizedBox(
              width: 350,
              height: 400,
              child: Column(children: [
                TextField(
                  controller: search,
                  decoration: const InputDecoration(
                    hintText: 'بحث...',
                    hintStyle: TextStyle(fontFamily: 'Cairo'),
                    prefixIcon: Icon(Icons.search),
                  ),
                  onChanged: (v) {
                    setS(() {
                      final q = v.toLowerCase();
                      filtered = _clients.where((c) {
                        final name = (c['name'] ?? '').toString().toLowerCase();
                        return name.contains(q);
                      }).toList();
                    });
                  },
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      return ListTile(
                        title: Text(c['name'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
                        subtitle: Text(c['phone'] ?? '', style: const TextStyle(fontFamily: 'Cairo')),
                        onTap: () {
                          setState(() {
                            _clientId = c['id'] as int?;
                            _clientName = c['name'] ?? '';
                            _clientPhone = c['phone'] ?? '';
                            _clientCtrl.text = _clientName;
                            _clientPhoneCtrl.text = _clientPhone;
                          });
                          Navigator.pop(context);
                        },
                      );
                    },
                  ),
                ),
              ]),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
              ),
            ],
          );
        });
      },
    );
  }

  // ── BUILD ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final isNew = widget.saleId == null;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: AppBar(
        backgroundColor: _blue,
        foregroundColor: Colors.white,
        title: Text(
          isNew ? 'وصل بيع جديد / Nouveau document' : 'تعديل / $_saleCode',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: Colors.white),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: 'طباعة / Imprimer',
            onPressed: _printDoc,
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_rounded),
              tooltip: 'حفظ / Enregistrer',
              onPressed: _save,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // ── Header form ────────────────────────────────────────────
                _buildHeaderCard(),
                // ── Items header ───────────────────────────────────────────
                _buildItemsHeader(),
                // ── Items list ─────────────────────────────────────────────
                Expanded(child: _buildItemsList()),
                // ── Totals footer ──────────────────────────────────────────
                _buildTotalsBar(),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        backgroundColor: _cyan,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add),
        label: const Text('إضافة عنصر', style: TextStyle(fontFamily: 'Cairo')),
        onPressed: _openItemPicker,
      ),
    );
  }

  // ── Header card ───────────────────────────────────────────────────────────
  Widget _buildHeaderCard() {
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // Row 1: sale code + date
          Row(children: [
            Expanded(
              child: Text(
                _saleCode,
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: _blue),
              ),
            ),
            InkWell(
              onTap: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: _saleDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2030),
                );
                if (picked != null) setState(() => _saleDate = picked);
              },
              child: Row(children: [
                const Icon(Icons.calendar_today_rounded, size: 16, color: _blue),
                const SizedBox(width: 4),
                Text(
                  DateFormat('dd/MM/yyyy').format(_saleDate),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                ),
              ]),
            ),
          ]),
          const SizedBox(height: 8),
          // Row 2: doc type + status
          Row(children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _docType,
                decoration: const InputDecoration(
                  labelText: 'نوع الوثيقة / Type',
                  labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 'bon_livraison', child: Text('وصل تسليم', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'bon_commande', child: Text('طلب بيع', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'facture', child: Text('فاتورة', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'bon_route', child: Text('وصل شحن', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'devis', child: Text('عرض سعر', style: TextStyle(fontFamily: 'Cairo'))),
                ],
                onChanged: (v) => setState(() => _docType = v ?? _docType),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: DropdownButtonFormField<String>(
                value: _status,
                decoration: const InputDecoration(
                  labelText: 'الحالة / Statut',
                  labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  isDense: true,
                  border: OutlineInputBorder(),
                ),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('مسودة', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'confirmed', child: Text('مؤكد', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'delivered', child: Text('تم التسليم', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'paid', child: Text('مدفوع', style: TextStyle(fontFamily: 'Cairo'))),
                  DropdownMenuItem(value: 'cancelled', child: Text('ملغى', style: TextStyle(fontFamily: 'Cairo'))),
                ],
                onChanged: (v) => setState(() => _status = v ?? _status),
              ),
            ),
          ]),
          const SizedBox(height: 8),
          // Row 3: client
          GestureDetector(
            onTap: _openClientPicker,
            child: AbsorbPointer(
              child: TextField(
                controller: _clientCtrl,
                decoration: InputDecoration(
                  labelText: 'العميل / Client',
                  labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  isDense: true,
                  border: const OutlineInputBorder(),
                  suffixIcon: const Icon(Icons.person_search_rounded, color: _blue),
                ),
                style: const TextStyle(fontFamily: 'Cairo'),
                onChanged: (v) => setState(() => _clientName = v),
              ),
            ),
          ),
          const SizedBox(height: 8),
          // Row 4: phone + notes
          TextField(
            controller: _notesCtrl,
            decoration: const InputDecoration(
              labelText: 'ملاحظات / Notes',
              labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
              isDense: true,
              border: OutlineInputBorder(),
            ),
            style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
            onChanged: (v) => _notes = v,
            maxLines: 1,
          ),
        ]),
      ),
    );
  }

  // ── Items header ──────────────────────────────────────────────────────────
  Widget _buildItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: _blue.withOpacity(0.08),
      child: Row(children: const [
        Expanded(flex: 4, child: Text('المنتج / Article', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold))),
        SizedBox(width: 60, child: Text('الوحدة', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        SizedBox(width: 60, child: Text('الكمية', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center)),
        SizedBox(width: 80, child: Text('السعر', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        SizedBox(width: 90, child: Text('المجموع', style: TextStyle(fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.right)),
        SizedBox(width: 40),
      ]),
    );
  }

  // ── Items list ────────────────────────────────────────────────────────────
  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Center(
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.inventory_2_outlined, size: 64, color: Colors.grey.shade300),
          const SizedBox(height: 12),
          const Text('لا توجد عناصر\nأضف منتجات من الزر في الأسفل',
              textAlign: TextAlign.center, style: TextStyle(fontFamily: 'Cairo', color: Colors.grey)),
        ]),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.only(bottom: 80),
      itemCount: _items.length,
      itemBuilder: (_, i) {
        final item = _items[i];
        final total = (item['total_price'] as num?)?.toDouble() ?? 0.0;
        final qty = (item['quantity'] as num?)?.toDouble() ?? 1.0;
        final price = (item['unit_price'] as num?)?.toDouble() ?? 0.0;
        final colorName = item['color_name'] as String? ?? '';
        return Container(
          decoration: BoxDecoration(
            color: i.isEven ? Colors.white : const Color(0xFFF8FAFF),
            border: const Border(bottom: BorderSide(color: Color(0xFFE5E7EB), width: 0.5)),
          ),
          child: InkWell(
            onTap: () => _editItemDialog(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(children: [
                Expanded(
                  flex: 4,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(item['item_name'] ?? '', style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w600)),
                    if (colorName.isNotEmpty)
                      Text(colorName, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, color: Colors.blueGrey)),
                  ]),
                ),
                SizedBox(
                  width: 60,
                  child: Text(item['unit'] ?? '', textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                SizedBox(
                  width: 60,
                  child: Text(_fmt.format(qty), textAlign: TextAlign.center, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                SizedBox(
                  width: 80,
                  child: Text(_fmt.format(price), textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                ),
                SizedBox(
                  width: 90,
                  child: Text('${_fmt.format(total)} DA', textAlign: TextAlign.right, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.bold, color: _blue)),
                ),
                SizedBox(
                  width: 40,
                  child: IconButton(
                    icon: const Icon(Icons.remove_circle_outline_rounded, color: _red, size: 20),
                    onPressed: () => _removeItem(i),
                    padding: EdgeInsets.zero,
                  ),
                ),
              ]),
            ),
          ),
        );
      },
    );
  }

  // ── Totals footer ─────────────────────────────────────────────────────────
  Widget _buildTotalsBar() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 8, offset: const Offset(0, -2))],
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        // Discount + paid
        Row(children: [
          Expanded(
            child: TextField(
              controller: _discountCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Remise / خصم (DA)',
                labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              onChanged: (_) => _recalc(),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _paidCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'المبلغ المدفوع / Versé',
                labelStyle: TextStyle(fontFamily: 'Cairo', fontSize: 12),
                isDense: true,
                border: OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              onChanged: (_) => _recalc(),
            ),
          ),
        ]),
        const SizedBox(height: 8),
        // Totals display
        Row(children: [
          _totalChip('Sous-total', _fmt.format(_subtotal), Colors.grey.shade700),
          const SizedBox(width: 8),
          _totalChip('Remise', _fmt.format(_discountAmount), _red),
          const SizedBox(width: 8),
          _totalChip('Net à payer', _fmt.format(_netTotal), _blue, isBold: true),
          const SizedBox(width: 8),
          _totalChip('Reste', _fmt.format(_remainingAmount), _remainingAmount > 0 ? _red : _green),
        ]),
      ]),
    );
  }

  Widget _totalChip(String label, String value, Color color, {bool isBold = false}) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Text(label, style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: color)),
          Text(
            '$value DA',
            style: TextStyle(
              fontFamily: 'Cairo',
              fontSize: isBold ? 13 : 12,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: color,
            ),
          ),
        ]),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// ITEM PICKER BOTTOM SHEET
// ═══════════════════════════════════════════════════════════════════════════

class _ItemPickerSheet extends StatefulWidget {
  final SqlDatabase db;
  final void Function(Map<String, dynamic>) onItemSelected;

  const _ItemPickerSheet({required this.db, required this.onItemSelected});

  @override
  State<_ItemPickerSheet> createState() => _ItemPickerSheetState();
}

class _ItemPickerSheetState extends State<_ItemPickerSheet> {
  static const _blue = Color(0xFF1E3A8A);

  String _selectedCategory = 'Sections';
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  bool _loading = false;

  final List<Map<String, String>> _categories = [
    {'id': 'Sections', 'label': 'مقاطع', 'icon': 'architecture'},
    {'id': 'Accessories', 'label': 'إكسسوارات', 'icon': 'handyman'},
    {'id': 'Glass', 'label': 'زجاج', 'icon': 'window'},
    {'id': 'Joints', 'label': 'جوانات', 'icon': 'linear_scale'},
    {'id': 'ShutterComponents', 'label': 'ستائر', 'icon': 'blinds'},
    {'id': 'Sheets', 'label': 'ألواح', 'icon': 'view_agenda'},
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      final q = _searchCtrl.text.trim().toLowerCase();
      List<Map<String, dynamic>> items = [];
      switch (_selectedCategory) {
        case 'Sections':
          if (q.isNotEmpty) {
            items = await widget.db.searchSectionsWithProfile(q);
          } else {
            items = await widget.db.searchSectionsWithProfile('');
          }
          break;
        case 'Accessories':
          items = await widget.db.readAccessories();
          break;
        case 'Glass':
          items = await widget.db.readGlass();
          break;
        case 'Joints':
          items = await widget.db.readJoints();
          break;
        case 'ShutterComponents':
          items = await widget.db.readShutterComponents();
          break;
        case 'Sheets':
          items = await widget.db.readStandardSheets();
          break;
      }
      if (q.isNotEmpty && _selectedCategory != 'Sections') {
        items = items.where((item) {
          final name = (item['name'] ?? item['type'] ?? '').toString().toLowerCase();
          final code = (item['code'] ?? '').toString().toLowerCase();
          return name.contains(q) || code.contains(q);
        }).toList();
      }
      setState(() => _items = items);
    } finally {
      setState(() => _loading = false);
    }
  }

  void _selectItem(Map<String, dynamic> item) {
    final qtyCtrl = TextEditingController(text: '1');
    final priceCtrl = TextEditingController(
      text: _getDefaultPrice(item).toStringAsFixed(2),
    );

    // Determine unit
    String unit = _getUnit();
    String colorName = '';
    int? colorId;

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(
          item['name'] ?? item['type'] ?? 'Article',
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: qtyCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Quantité / الكمية',
                labelStyle: TextStyle(fontFamily: 'Cairo'),
                isDense: true,
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                labelText: 'Prix unitaire / السعر',
                labelStyle: TextStyle(fontFamily: 'Cairo'),
                isDense: true,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () {
              final qty = double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
              final price = double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
              widget.onItemSelected({
                'item_type': _selectedCategory,
                'item_id': item['id'] ?? 0,
                'item_code': item['code'] ?? item['name'] ?? '',
                'item_name': item['name'] ?? item['type'] ?? '',
                'color_id': colorId,
                'color_name': colorName,
                'unit': unit,
                'length_mm': (item['length_mm'] ?? 0.0) as double? ?? 0.0,
                'width_mm': (item['width_mm'] ?? 0.0) as double? ?? 0.0,
                'quantity': qty,
                'unit_price': price,
                'total_price': qty * price,
                'notes': '',
              });
              Navigator.pop(context); // close dialog
              Navigator.pop(context); // close bottom sheet
            },
            child: const Text('إضافة', style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }

  double _getDefaultPrice(Map<String, dynamic> item) {
    final p = item['price'] ?? item['price_per_sqm'] ?? item['price_per_sheet'] ?? 0.0;
    return (p as num?)?.toDouble() ?? 0.0;
  }

  String _getUnit() {
    switch (_selectedCategory) {
      case 'Sections': return 'barre';
      case 'Accessories': return 'pcs';
      case 'Glass': return 'm²';
      case 'Joints': return 'm';
      case 'ShutterComponents': return 'pcs';
      case 'Sheets': return 'feuille';
      default: return 'pcs';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(children: [
        // Handle
        Center(
          child: Container(
            margin: const EdgeInsets.only(top: 10, bottom: 6),
            width: 40,
            height: 4,
            decoration: BoxDecoration(color: Colors.grey.shade300, borderRadius: BorderRadius.circular(2)),
          ),
        ),
        // Title
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(children: [
            const Text('اختر منتجاً / Choisir article',
                style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 16, color: _blue)),
            const Spacer(),
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.pop(context),
            ),
          ]),
        ),
        // Category tabs
        SizedBox(
          height: 44,
          child: ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: _categories.length,
            itemBuilder: (_, i) {
              final cat = _categories[i];
              final selected = _selectedCategory == cat['id'];
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(cat['label']!, style: TextStyle(fontFamily: 'Cairo', fontSize: 12, color: selected ? Colors.white : _blue)),
                  selected: selected,
                  selectedColor: _blue,
                  backgroundColor: Colors.transparent,
                  side: const BorderSide(color: _blue),
                  onSelected: (_) {
                    setState(() => _selectedCategory = cat['id']!);
                    _loadItems();
                  },
                  showCheckmark: false,
                ),
              );
            },
          ),
        ),
        // Search
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: TextField(
            controller: _searchCtrl,
            decoration: InputDecoration(
              hintText: 'بحث... / Rechercher...',
              hintStyle: const TextStyle(fontFamily: 'Cairo'),
              prefixIcon: const Icon(Icons.search, color: _blue),
              isDense: true,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onChanged: (_) => _loadItems(),
          ),
        ),
        // Items
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _items.isEmpty
                  ? const Center(child: Text('لا توجد نتائج', style: TextStyle(fontFamily: 'Cairo')))
                  : ListView.separated(
                      itemCount: _items.length,
                      separatorBuilder: (_, __) => const Divider(height: 1),
                      itemBuilder: (_, i) {
                        final item = _items[i];
                        final name = item['name'] ?? item['type'] ?? '';
                        final code = item['code'] ?? '';
                        final price = _getDefaultPrice(item);
                        return ListTile(
                          leading: CircleAvatar(
                            backgroundColor: _blue.withOpacity(0.1),
                            child: Text(
                              _selectedCategory.substring(0, 1),
                              style: const TextStyle(color: _blue, fontWeight: FontWeight.bold),
                            ),
                          ),
                          title: Text(name, style: const TextStyle(fontFamily: 'Cairo', fontSize: 13)),
                          subtitle: code.isNotEmpty ? Text(code, style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)) : null,
                          trailing: price > 0
                              ? Text(
                                  NumberFormat('#,##0.00').format(price),
                                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 12, color: _blue, fontWeight: FontWeight.bold),
                                )
                              : null,
                          onTap: () => _selectItem(item),
                        );
                      },
                    ),
        ),
      ]),
    );
  }
}
