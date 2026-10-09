import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:provider/provider.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../sql_database.dart';
import '../services/cloud_sync_service.dart';
import '../services/material_sale_pdf_service.dart';
import '../utils/decimal_text_input_formatter.dart';

class MaterialSaleEditorScreen extends StatefulWidget {
  final SqlDatabase db;
  final int? saleId; // null = create new
  final String? initialDocType;

  const MaterialSaleEditorScreen({
    super.key,
    required this.db,
    this.saleId,
    this.initialDocType,
  });

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

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }

  // ── Sale header fields ────────────────────────────────────────────────────
  String _saleCode = '';
  String _docType = 'bon_commande';
  String _status = 'draft';
  int? _clientId;
  String _clientName = '';
  String _clientPhone = '';
  String _notes = '';
  DateTime _saleDate = DateTime.now();

  int? _locationId;
  int? _destLocationId;
  bool _isInternal = false;
  int? _linkedAchatId;
  List<Map<String, dynamic>> _storeLocations = [];
  List<Map<String, dynamic>> _workshopLocations = [];

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

  bool get _isInternalClient {
    if (_isInternal) return true;
    final client = _clients.firstWhere(
      (c) => c['id'] == _clientId,
      orElse: () => <String, dynamic>{},
    );
    return client['business_segment'] == 'internal_workshop';
  }

  @override
  void initState() {
    super.initState();
    if (widget.saleId == null && widget.initialDocType != null) {
      _docType = widget.initialDocType!;
    }
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
      final settings = Provider.of<AppSettingsProvider>(context, listen: false);
      _storeLocations = await widget.db.readStoreLocations();
      if (_storeLocations.isNotEmpty) {
        final defaultStoreId = settings.defaultStoreLocationId;
        final match = _storeLocations.firstWhere(
          (l) => l['id'] == defaultStoreId,
          orElse: () => _storeLocations.first,
        );
        _locationId ??= match['id'];
      }

      if (settings.isDualActivity) {
        await widget.db.ensureInternalWorkshopClient();
        _clients = await widget.db.readMaterialClients(includeInternalWorkshop: true);
        _workshopLocations = await widget.db.readWorkshopLocations();
        if (_workshopLocations.isNotEmpty) {
          final defaultWsId = settings.defaultWorkshopLocationId;
          final match = _workshopLocations.firstWhere(
            (l) => l['id'] == defaultWsId,
            orElse: () => _workshopLocations.first,
          );
          _destLocationId ??= match['id'];
        }
      } else {
        _clients = await widget.db.readMaterialClients(includeInternalWorkshop: false);
      }

      if (widget.saleId != null) {
        final sale = await widget.db.readMaterialSaleById(widget.saleId!);
        if (sale != null) {
          _saleCode = sale['sale_code'] ?? '';
          _docType = sale['doc_type'] ?? 'bon_commande';
          _status = sale['status'] ?? 'draft';
          _clientId = sale['client_id'] as int?;
          _clientName = sale['client_name'] ?? '';
          _clientPhone = sale['client_phone'] ?? '';
          _notes = sale['notes'] ?? '';
          _discountAmount =
              (sale['discount_amount'] as num?)?.toDouble() ?? 0.0;
          _paidAmount = (sale['paid_amount'] as num?)?.toDouble() ?? 0.0;
          _locationId = (sale['location_id'] as num?)?.toInt() ?? _locationId;
          _destLocationId = (sale['dest_location_id'] as num?)?.toInt() ?? _destLocationId;
          _isInternal = (sale['is_internal'] as num?)?.toInt() == 1;
          _linkedAchatId = (sale['linked_achat_id'] as num?)?.toInt();
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
  double get _subtotal => _items.fold(
    0.0,
    (s, i) => s + ((i['total_price'] as num?)?.toDouble() ?? 0.0),
  );

  double get _netTotal =>
      (_subtotal - _discountAmount).clamp(0.0, double.infinity);

  double get _remainingAmount =>
      (_netTotal - _paidAmount).clamp(0.0, double.infinity);

  bool get _shouldDeductStock {
    if (_status != 'confirmed' && _status != 'delivered') return false;
    return _docType == 'bon_livraison' ||
        _docType == 'bon_route' ||
        _docType == 'facture';
  }

  void _recalc() => setState(() {
    _discountAmount =
        double.tryParse(_discountCtrl.text.replaceAll(',', '.')) ?? 0.0;
    _paidAmount = double.tryParse(_paidCtrl.text.replaceAll(',', '.')) ?? 0.0;
  });

  String _statusHelpText() {
    switch (_status) {
      case 'draft':
        return _t('مسودة: الوثيقة قيد التحضير ولا تغيّر المخزون.');
      case 'reserved':
        return _t('محجوز: الكمية مخصّصة للعميل ولم تُسلّم بعد.');
      case 'confirmed':
        return _t('مؤكد: تم اعتماد الوثيقة وأصبحت جاهزة للتنفيذ.');
      case 'delivered':
        return _t('تم التسليم: خرجت المواد وسُلّمت للعميل.');
      case 'paid':
        return _t('مدفوع: تم تسديد المبلغ الكامل للوثيقة.');
      case 'cancelled':
        return _t('ملغى: الوثيقة متوقفة ولا تُنفّذ.');
      default:
        return '';
    }
  }

  bool _sameSaleItem(Map<String, dynamic> first, Map<String, dynamic> second) {
    return ((first['item_id'] as num?)?.toInt() ?? 0) ==
            ((second['item_id'] as num?)?.toInt() ?? 0) &&
        (first['item_type']?.toString() ?? '') ==
            (second['item_type']?.toString() ?? '') &&
        (first['color_id'] as num?)?.toInt() ==
            (second['color_id'] as num?)?.toInt();
  }

  bool get _hasDuplicateItems {
    for (var i = 0; i < _items.length; i++) {
      for (var j = i + 1; j < _items.length; j++) {
        if (_sameSaleItem(_items[i], _items[j])) return true;
      }
    }
    return false;
  }

  // ── Save ──────────────────────────────────────────────────────────────────
  Future<void> _save() async {
    if (_clientName.trim().isEmpty) {
      _showSnack(_t('يرجى اختيار العميل'), isError: true);
      return;
    }
    if (_hasDuplicateItems) {
      _showSnack(
        _t('يوجد عنصر مكرر. احتفظ بسطر واحد وعدّل كميته.'),
        isError: true,
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final saleDateStr = _saleDate.toUtc().toIso8601String();

      final isInternal = _isInternalClient;
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
          locationId: _locationId ?? 1,
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
          if (isInternal && _destLocationId != null && _shouldDeductStock) {
            await widget.db.executeInternalMaterialSaleTransfer(
              saleId: newId,
              destLocationId: _destLocationId!,
            );
          } else if (_shouldDeductStock) {
            await widget.db.deductStockForMaterialSale(
              newId,
              locationId: _locationId ?? 1,
            );
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
        if (isInternal && _destLocationId != null && _shouldDeductStock) {
          await widget.db.executeInternalMaterialSaleTransfer(
            saleId: widget.saleId!,
            destLocationId: _destLocationId!,
          );
        } else if (_shouldDeductStock) {
          await widget.db.deductStockForMaterialSale(
            widget.saleId!,
            locationId: _locationId ?? 1,
          );
        }
      }

      CloudSyncService().notifyChange();
      if (mounted) {
        _showSnack('${_t('تم الحفظ بنجاح')} ✔', isError: false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('${_t('خطأ في الحفظ')}: $e', isError: true);
    } finally {
      setState(() => _isSaving = false);
    }
  }

  // ── Reverse Internal Transfer (إلغاء التحويل واسترجاع المواد للمحل) ───────────
  Future<void> _reverseInternalTransfer() async {
    if (widget.saleId == null) return;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          _t('إلغاء التحويل الداخلي'),
          style: const TextStyle(fontWeight: FontWeight.bold),
        ),
        content: Text(
          _t('هل أنت متأكد من إلغاء هذا التحويل الداخلي؟ سيتم إرجاع المواد من مستودع الورشة إلى مستودع المحل وتوثيق حركة عكسية دون حذف السجل التاريخي.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(_t('تراجع')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(_t('تأكيد الإرجاع للمحل')),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    setState(() => _isSaving = true);
    try {
      await widget.db.cancelOrReverseInternalMaterialSaleTransfer(saleId: widget.saleId!);
      if (mounted) {
        _showSnack('${_t('تم إرجاع المواد وإلغاء التحويل الداخلي بنجاح')} ✔', isError: false);
        Navigator.pop(context, true);
      }
    } catch (e) {
      _showSnack('${_t('خطأ أثناء إلغاء التحويل')}: $e', isError: true);
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Print ─────────────────────────────────────────────────────────────────
  Future<void> _printDoc() async {
    if (widget.saleId == null && _items.isEmpty) {
      _showSnack(_t('يرجى إضافة عنصر واحد على الأقل'), isError: true);
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
      final bytes = await MaterialSalePdfService.generate(
        sale: sale,
        items: _items,
      );
      await MaterialSalePdfService.printOrShare(bytes, _saleCode);
    } catch (e) {
      _showSnack('${_t('خطأ في الطباعة')}: $e', isError: true);
    }
  }

  void _showSnack(String msg, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(fontFamily: 'Cairo')),
        backgroundColor: isError ? _red : _green,
      ),
    );
  }

  // ── Add item ──────────────────────────────────────────────────────────────
  void _openItemPicker() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => Dialog(
        insetPadding: const EdgeInsets.all(18),
        clipBehavior: Clip.antiAlias,
        child: _ItemPickerSheet(
          db: widget.db,
          onItemSelected: (item) {
            final alreadyAdded = _items.any(
              (existing) => _sameSaleItem(existing, item),
            );
            if (alreadyAdded) {
              _showSnack(
                _t('هذا العنصر مضاف مسبقًا. عدّل كميته من السطر الموجود.'),
                isError: true,
              );
              return;
            }
            setState(() => _items.add(item));
          },
        ),
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
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [
                DecimalTextInputFormatter(decimalDigits: 3),
              ],
              decoration: InputDecoration(
                labelText: _t('الكمية'),
                labelStyle: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: priceCtrl,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              inputFormatters: const [DecimalTextInputFormatter()],
              decoration: InputDecoration(
                labelText: _t('سعر الوحدة'),
                labelStyle: const TextStyle(fontFamily: 'Cairo'),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(
              _t('إلغاء'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _blue),
            onPressed: () {
              final qty =
                  double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 1.0;
              final price =
                  double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
              setState(() {
                _items[index]['quantity'] = qty;
                _items[index]['unit_price'] = price;
                _items[index]['total_price'] = qty * price;
              });
              Navigator.pop(context);
            },
            child: Text(
              _t('حفظ'),
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  // ── Client picker dialog ───────────────────────────────────────────────────
  String _clientDisplayName(Map<String, dynamic> client) {
    final direct = client['name']?.toString().trim() ?? '';
    if (direct.isNotEmpty) return direct;
    return [client['firstname'], client['lastname']]
        .map((value) => value?.toString().trim() ?? '')
        .where((value) => value.isNotEmpty)
        .join(' ');
  }

  String _clientPhoneOf(Map<String, dynamic> client) =>
      (client['phone1'] ?? client['phone'] ?? '').toString();

  Future<Map<String, dynamic>?> _addMaterialClient() async {
    final firstNameCtrl = TextEditingController();
    final lastNameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final result = await showDialog<Map<String, String>>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(
          _t('إضافة زبون مواد جديد'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: firstNameCtrl,
              decoration: InputDecoration(labelText: _t('الاسم')),
            ),
            TextField(
              controller: lastNameCtrl,
              decoration: InputDecoration(labelText: _t('اللقب')),
            ),
            TextField(
              controller: phoneCtrl,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(labelText: _t('رقم الهاتف')),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(_t('إلغاء')),
          ),
          FilledButton(
            onPressed: () {
              if (firstNameCtrl.text.trim().isEmpty) return;
              Navigator.pop(dialogContext, {
                'firstname': firstNameCtrl.text.trim(),
                'lastname': lastNameCtrl.text.trim(),
                'phone': phoneCtrl.text.trim(),
              });
            },
            child: Text(_t('إضافة')),
          ),
        ],
      ),
    );
    firstNameCtrl.dispose();
    lastNameCtrl.dispose();
    phoneCtrl.dispose();
    if (result == null) return null;
    final id = await widget.db.insertClient(
      result['firstname']!,
      result['lastname']!,
      result['phone']!,
      '',
      '',
      '',
    );
    await widget.db.setClientBusinessSegment(id, 'materials');
    final clients = await widget.db.readMaterialClients();
    _clients = clients;
    for (final client in clients) {
      if (client['id'] == id) return client;
    }
    return null;
  }

  void _openClientPicker() {
    showDialog(
      context: context,
      builder: (_) {
        final search = TextEditingController();
        List<Map<String, dynamic>> filtered = List.from(_clients);
        var includeWindowClients = false;
        return StatefulBuilder(
          builder: (ctx, setS) {
            void applySearch(List<Map<String, dynamic>> source) {
              final q = search.text.trim().toLowerCase();
              filtered = source.where((client) {
                return _clientDisplayName(client).toLowerCase().contains(q) ||
                    _clientPhoneOf(client).toLowerCase().contains(q);
              }).toList();
            }

            return AlertDialog(
              title: Text(
                _t('اختر عميلاً'),
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 14),
              ),
              content: SizedBox(
                width: 350,
                height: 400,
                child: Column(
                  children: [
                    TextField(
                      controller: search,
                      decoration: InputDecoration(
                        hintText: _t('بحث...'),
                        hintStyle: const TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.search),
                      ),
                      onChanged: (v) {
                        setS(() => applySearch(_clients));
                      },
                    ),
                    SwitchListTile.adaptive(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      value: includeWindowClients,
                      title: Text(
                        _t('إظهار زبائن النوافذ أيضًا'),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 12,
                        ),
                      ),
                      onChanged: (value) async {
                        final clients = await widget.db.readMaterialClients(
                          includeWindowClients: value,
                        );
                        if (!ctx.mounted) return;
                        setS(() {
                          includeWindowClients = value;
                          _clients = clients;
                          applySearch(clients);
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
                            title: Text(
                              _clientDisplayName(c),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            subtitle: Text(
                              _clientPhoneOf(c),
                              style: const TextStyle(fontFamily: 'Cairo'),
                            ),
                            trailing: Text(
                              c['business_segment'] == 'internal_workshop'
                                  ? _t('داخلي (الورشة)')
                                  : c['business_segment'] == 'both'
                                  ? _t('مشترك')
                                  : c['business_segment'] == 'materials'
                                  ? _t('مواد')
                                  : _t('نوافذ'),
                              style: TextStyle(
                                fontFamily: 'Cairo',
                                fontSize: 10,
                                fontWeight: c['business_segment'] == 'internal_workshop'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                                color: c['business_segment'] == 'internal_workshop'
                                    ? Colors.amber.shade800
                                    : null,
                              ),
                            ),
                            onTap: () async {
                              final isInternalSeg =
                                  c['business_segment'] == 'internal_workshop';
                              if (c['business_segment'] == 'windows') {
                                await widget.db.setClientBusinessSegment(
                                  c['id'] as int,
                                  'both',
                                );
                              }
                              if (!mounted) return;
                              setState(() {
                                _clientId = c['id'] as int?;
                                _clientName = _clientDisplayName(c);
                                _clientPhone = _clientPhoneOf(c);
                                _isInternal = isInternalSeg;
                                _clientCtrl.text = _clientName;
                                _clientPhoneCtrl.text = _clientPhone;
                              });
                              Navigator.pop(ctx);
                            },
                          );
                        },
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton.icon(
                  onPressed: () async {
                    final client = await _addMaterialClient();
                    if (client == null || !ctx.mounted) return;
                    setS(() => applySearch(_clients));
                  },
                  icon: const Icon(Icons.person_add_alt_1_rounded),
                  label: Text(_t('زبون مواد جديد')),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: Text(
                    _t('إلغاء'),
                    style: const TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
              ],
            );
          },
        );
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
          isNew ? _t('وثيقة جديدة') : '${_t('تعديل الوثيقة')} / $_saleCode',
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontSize: 15,
            color: Colors.white,
          ),
        ),
        actions: [
          if (widget.saleId != null && _isInternal && _status == 'delivered')
            IconButton(
              icon: const Icon(Icons.undo_rounded, color: Colors.orangeAccent),
              tooltip: _t('إرجاع المواد وإلغاء التحويل'),
              onPressed: _reverseInternalTransfer,
            ),
          IconButton(
            icon: const Icon(Icons.print_rounded),
            tooltip: _t('طباعة'),
            onPressed: _printDoc,
          ),
          if (_isSaving)
            const Padding(
              padding: EdgeInsets.all(12),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.save_rounded),
              tooltip: _t('حفظ'),
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
        label: Text(
          _t('إضافة عنصر'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        onPressed: _openItemPicker,
      ),
    );
  }

  // ── Header card ───────────────────────────────────────────────────────────
  Widget _buildHeaderCard() {
    final fieldTextColor = Theme.of(context).colorScheme.onSurface;
    final surfaceColor = Theme.of(context).colorScheme.surface;
    return Card(
      margin: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: sale code + date
            Row(
              children: [
                Expanded(
                  child: Text(
                    _saleCode,
                    style: const TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: _blue,
                    ),
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
                  child: Row(
                    children: [
                      const Icon(
                        Icons.calendar_today_rounded,
                        size: 16,
                        color: _blue,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        DateFormat('dd/MM/yyyy').format(_saleDate),
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 2: doc type + status
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _docType,
                    dropdownColor: surfaceColor,
                    iconEnabledColor: fieldTextColor,
                    decoration: InputDecoration(
                      labelText: _t('نوع الوثيقة'),
                      labelStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: fieldTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'bon_commande',
                        child: Text(
                          _t('طلب مواد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'bon_livraison',
                        child: Text(
                          _t('وصل تسليم مواد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'bon_route',
                        child: Text(
                          _t('وصل مسار مواد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'facture',
                        child: Text(
                          _t('فاتورة مواد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'devis',
                        child: Text(
                          _t('فاتورة أولية مواد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _docType = v ?? _docType),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _status,
                    dropdownColor: surfaceColor,
                    iconEnabledColor: fieldTextColor,
                    decoration: InputDecoration(
                      labelText: _t('الحالة'),
                      labelStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                      ),
                      isDense: true,
                      border: const OutlineInputBorder(),
                    ),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                      color: fieldTextColor,
                      fontWeight: FontWeight.w500,
                    ),
                    items: [
                      DropdownMenuItem(
                        value: 'draft',
                        child: Text(
                          _t('مسودة'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'reserved',
                        child: Text(
                          _t('محجوز'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'confirmed',
                        child: Text(
                          _t('مؤكد'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'delivered',
                        child: Text(
                          _t('تم التسليم'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'paid',
                        child: Text(
                          _t('مدفوع'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                      DropdownMenuItem(
                        value: 'cancelled',
                        child: Text(
                          _t('ملغى'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            color: fieldTextColor,
                          ),
                        ),
                      ),
                    ],
                    onChanged: (v) => setState(() => _status = v ?? _status),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.info_outline_rounded,
                  size: 15,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 5),
                Expanded(
                  child: Text(
                    _statusHelpText(),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 10.5,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            // Row 3: client
            GestureDetector(
              onTap: _openClientPicker,
              child: AbsorbPointer(
                child: TextField(
                  controller: _clientCtrl,
                  decoration: InputDecoration(
                    labelText: _t('العميل'),
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                    suffixIcon: const Icon(
                      Icons.person_search_rounded,
                      color: _blue,
                    ),
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
              decoration: InputDecoration(
                labelText: _t('ملاحظات'),
                labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                isDense: true,
                border: const OutlineInputBorder(),
              ),
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
              onChanged: (v) => _notes = v,
              maxLines: 1,
            ),
            if (_storeLocations.isNotEmpty) ...[
              const SizedBox(height: 8),
              DropdownButtonFormField<int>(
                value: _locationId,
                isDense: true,
                decoration: InputDecoration(
                  labelText: _t('مستودع المحل (المصدر)'),
                  labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                  prefixIcon: const Icon(Icons.storefront_rounded, size: 18),
                  border: const OutlineInputBorder(),
                ),
                items: _storeLocations.map((loc) {
                  return DropdownMenuItem<int>(
                    value: (loc['id'] as num).toInt(),
                    child: Text(
                      loc['name']?.toString() ?? '',
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                    ),
                  );
                }).toList(),
                onChanged: (val) => setState(() => _locationId = val),
              ),
            ],
            if (_isInternalClient) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.12),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: Colors.amber.shade700),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.swap_horiz_rounded, color: Colors.amber.shade800, size: 20),
                        const SizedBox(width: 8),
                        Text(
                          _t('بيع داخلي للورشة (تحويل مخزون تلقائي)'),
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.bold,
                            fontSize: 12.5,
                            color: Colors.amber.shade900,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    if (_workshopLocations.isNotEmpty)
                      DropdownButtonFormField<int>(
                        value: _destLocationId,
                        isDense: true,
                        decoration: InputDecoration(
                          labelText: _t('مستودع الورشة (المستلم)'),
                          labelStyle: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                          prefixIcon: const Icon(Icons.precision_manufacturing_rounded, size: 18),
                          border: const OutlineInputBorder(),
                        ),
                        items: _workshopLocations.map((loc) {
                          return DropdownMenuItem<int>(
                            value: (loc['id'] as num).toInt(),
                            child: Text(
                              loc['name']?.toString() ?? '',
                              style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                            ),
                          );
                        }).toList(),
                        onChanged: (val) => setState(() => _destLocationId = val),
                      ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Items header ──────────────────────────────────────────────────────────
  Widget _buildItemsHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: _blue.withOpacity(0.08),
      child: Row(
        children: [
          Expanded(
            flex: 4,
            child: Text(
              _t('المنتج'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _t('الوحدة'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 60,
            child: Text(
              _t('الكمية'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(
            width: 80,
            child: Text(
              _t('السعر'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          SizedBox(
            width: 90,
            child: Text(
              _t('المجموع'),
              style: const TextStyle(
                fontFamily: 'Cairo',
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.right,
            ),
          ),
          const SizedBox(width: 40),
        ],
      ),
    );
  }

  // ── Items list ────────────────────────────────────────────────────────────
  Widget _buildItemsList() {
    if (_items.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.inventory_2_outlined,
              size: 64,
              color: Colors.grey.shade300,
            ),
            const SizedBox(height: 12),
            Text(
              '${_t('لا توجد عناصر')}\n${_t('أضف منتجات من الزر في الأسفل')}',
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', color: Colors.grey),
            ),
          ],
        ),
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
            color: i.isEven
                ? Theme.of(context).colorScheme.surface
                : Theme.of(context).colorScheme.surfaceContainerLow,
            border: Border(
              bottom: BorderSide(
                color: Theme.of(context).dividerColor,
                width: 0.5,
              ),
            ),
          ),
          child: InkWell(
            onTap: () => _editItemDialog(i),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 4,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item['item_name'] ?? '',
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (colorName.isNotEmpty)
                          Text(
                            colorName,
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 11,
                              color: Colors.blueGrey,
                            ),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      item['unit'] ?? '',
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      _fmt.format(qty),
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 80,
                    child: Text(
                      _fmt.format(price),
                      textAlign: TextAlign.right,
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: Text(
                      '${_fmt.format(total)} DA',
                      textAlign: TextAlign.right,
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        color: _blue,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 40,
                    child: IconButton(
                      icon: const Icon(
                        Icons.remove_circle_outline_rounded,
                        color: _red,
                        size: 20,
                      ),
                      onPressed: () => _removeItem(i),
                      padding: EdgeInsets.zero,
                    ),
                  ),
                ],
              ),
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
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).shadowColor.withOpacity(0.12),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Discount + paid
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _discountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [DecimalTextInputFormatter()],
                  decoration: InputDecoration(
                    labelText: '${_t('خصم')} (DA)',
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  onChanged: (_) => _recalc(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _paidCtrl,
                  keyboardType: const TextInputType.numberWithOptions(
                    decimal: true,
                  ),
                  inputFormatters: const [DecimalTextInputFormatter()],
                  decoration: InputDecoration(
                    labelText: _t('المبلغ المدفوع'),
                    labelStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 12,
                    ),
                    isDense: true,
                    border: const OutlineInputBorder(),
                  ),
                  style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
                  onChanged: (_) => _recalc(),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Totals display
          Row(
            children: [
              _totalChip(
                _t('المجموع الإجمالي'),
                _fmt.format(_subtotal),
                Colors.grey.shade700,
              ),
              const SizedBox(width: 8),
              _totalChip(_t('خصم'), _fmt.format(_discountAmount), _red),
              const SizedBox(width: 8),
              _totalChip(
                _t('المبلغ الصافي'),
                _fmt.format(_netTotal),
                _blue,
                isBold: true,
              ),
              const SizedBox(width: 8),
              _totalChip(
                _t('المبلغ المتبقي'),
                _fmt.format(_remainingAmount),
                _remainingAmount > 0 ? _red : _green,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _totalChip(
    String label,
    String value,
    Color color, {
    bool isBold = false,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Text(
              label,
              style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: color),
            ),
            Text(
              '$value DA',
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: isBold ? 13 : 12,
                fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
                color: color,
              ),
            ),
          ],
        ),
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

  String _t(String key) {
    final lang = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return Localization.translate(key, lang);
  }

  String _selectedCategory = 'Sections';
  String _selectedProfile = '';
  final _searchCtrl = TextEditingController();
  List<Map<String, dynamic>> _items = [];
  List<String> _profileNames = [];
  final Map<int, List<Map<String, dynamic>>> _sectionColorsByProfile = {};
  final Map<String, double> _stockQuantities = {};
  Map<String, dynamic>? _selectedItem;
  List<Map<String, dynamic>> _selectedItemColors = const [];
  int? _selectedColorId;
  String _selectedColorName = '';
  final _quantityCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController(text: '0.00');
  bool _loading = false;
  bool _stockLoaded = false;

  List<Map<String, String>> get _categories => [
    {'id': 'Sections', 'label': _t('مقاطع'), 'icon': 'architecture'},
    {'id': 'Accessories', 'label': _t('إكسسوارات'), 'icon': 'handyman'},
    {'id': 'Glass', 'label': _t('زجاج'), 'icon': 'window'},
    {'id': 'Joints', 'label': _t('جوانات'), 'icon': 'linear_scale'},
    {'id': 'ShutterComponents', 'label': _t('ستائر'), 'icon': 'blinds'},
    {'id': 'Sheets', 'label': _t('ألواح'), 'icon': 'view_agenda'},
  ];

  @override
  void initState() {
    super.initState();
    _loadItems();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _quantityCtrl.dispose();
    _priceCtrl.dispose();
    super.dispose();
  }

  String _canonicalStockType(String category) {
    switch (category) {
      case 'Sections':
        return 'Section';
      case 'Accessories':
        return 'Accessory';
      case 'ShutterComponents':
        return 'ShutterComponent';
      default:
        return category;
    }
  }

  String _stockKey(String category, int itemId, int? colorId) =>
      '${_canonicalStockType(category)}_${itemId}_${colorId ?? 0}';

  Future<void> _loadStockQuantities() async {
    if (_stockLoaded) return;
    final rows = await widget.db.readAllPossibleStock(1);
    for (final row in rows) {
      final type = row['item_type']?.toString() ?? '';
      final id = (row['item_id'] as num?)?.toInt() ?? 0;
      final colorId = (row['color_id'] as num?)?.toInt();
      _stockQuantities['${type}_${id}_${colorId ?? 0}'] =
          (row['quantity'] as num?)?.toDouble() ?? 0.0;
    }
    _stockLoaded = true;
  }

  double _stockFor(Map<String, dynamic> item, {int? colorId}) {
    final id = (item['id'] as num?)?.toInt() ?? 0;
    final selectedColor =
        colorId ?? (item['_selected_color_id'] as num?)?.toInt();
    return _stockQuantities[_stockKey(_selectedCategory, id, selectedColor)] ??
        0.0;
  }

  Future<void> _loadItems() async {
    setState(() => _loading = true);
    try {
      await _loadStockQuantities();
      final q = _searchCtrl.text.trim().toLowerCase();
      List<Map<String, dynamic>> items = [];
      switch (_selectedCategory) {
        case 'Sections':
          items = await widget.db.searchSectionsWithProfile('');
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
      if (_selectedCategory == 'Sections') {
        final profiles =
            items
                .map((item) => item['profile_name']?.toString().trim() ?? '')
                .where((name) => name.isNotEmpty)
                .toSet()
                .toList()
              ..sort();
        _profileNames = profiles;
        if (_selectedProfile.isNotEmpty &&
            !_profileNames.contains(_selectedProfile)) {
          _selectedProfile = '';
        }
        if (_selectedProfile.isNotEmpty) {
          items = items
              .where(
                (item) => item['profile_name']?.toString() == _selectedProfile,
              )
              .toList();
        }

        // A section is sold as a section/colour combination.  Showing one
        // row per available profile colour makes the selected stock variant
        // explicit before the quantity dialog is opened.
        final expanded = <Map<String, dynamic>>[];
        for (final item in items) {
          final profileId = (item['source_profile_id'] as num?)?.toInt();
          if (profileId == null) {
            expanded.add(item);
            continue;
          }
          final colors = _sectionColorsByProfile[profileId] ??= await widget.db
              .getColorsForProfile(profileId);
          if (colors.isEmpty) {
            expanded.add(item);
            continue;
          }
          for (final color in colors) {
            final variant = Map<String, dynamic>.from(item);
            variant['_selected_color_id'] = (color['id'] as num?)?.toInt();
            variant['_selected_color_name'] = color['name']?.toString() ?? '';
            variant['_selected_color_hex'] =
                color['hex_code']?.toString() ?? '';
            expanded.add(variant);
          }
        }
        items = expanded;
      } else {
        _selectedProfile = '';
        _profileNames = [];
      }
      if (q.isNotEmpty) {
        items = items.where((item) {
          final name = (item['name'] ?? item['type'] ?? '')
              .toString()
              .toLowerCase();
          final code = (item['code'] ?? '').toString().toLowerCase();
          final profile = (item['profile_name'] ?? '').toString().toLowerCase();
          final series = (item['series_name'] ?? '').toString().toLowerCase();
          return name.contains(q) ||
              code.contains(q) ||
              profile.contains(q) ||
              series.contains(q);
        }).toList();
      } else {
        items = [];
      }
      if (mounted) setState(() => _items = items);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<double> _resolvePrice(
    Map<String, dynamic> item, {
    int? colorId,
  }) async {
    final itemId = (item['id'] as num?)?.toInt() ?? 0;
    final latest = await widget.db.getLatestPurchasePrice(
      itemId: itemId,
      itemType: _selectedCategory,
      colorId: colorId,
    );
    if (latest != null && latest > 0) return latest;
    if (_selectedCategory == 'Sections' && colorId != null) {
      final catalogue = await widget.db.getSectionColorPrice(itemId, colorId);
      if (catalogue > 0) return catalogue;
    }
    return _getDefaultPrice(item);
  }

  Future<void> _selectItem(Map<String, dynamic> item) async {
    final colorId = (item['_selected_color_id'] as num?)?.toInt();
    final colorName = item['_selected_color_name']?.toString() ?? '';
    final profileId = (item['source_profile_id'] as num?)?.toInt();
    final availableColors = profileId == null
        ? const <Map<String, dynamic>>[]
        : (_sectionColorsByProfile[profileId] ??
              await widget.db.getColorsForProfile(profileId));
    final initialPrice = await _resolvePrice(item, colorId: colorId);
    if (!mounted) return;
    setState(() {
      _selectedItem = item;
      _selectedItemColors = availableColors;
      _selectedColorId = colorId;
      _selectedColorName = colorName;
      _quantityCtrl.text = '1';
      _priceCtrl.text = initialPrice.toStringAsFixed(2);
    });
  }

  void _addSelectedItem() {
    final item = _selectedItem;
    if (item == null) return;
    final qty = double.tryParse(_quantityCtrl.text.replaceAll(',', '.')) ?? 1.0;
    final price = double.tryParse(_priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
    widget.onItemSelected({
      'item_type': _selectedCategory,
      'item_id': item['id'] ?? 0,
      'item_code': item['code'] ?? item['name'] ?? '',
      'item_name': item['name'] ?? item['type'] ?? '',
      'color_id': _selectedColorId,
      'color_name': _selectedColorName,
      'unit': _getUnit(),
      'length_mm': (item['length_mm'] as num?)?.toDouble() ?? 0.0,
      'width_mm': (item['width_mm'] as num?)?.toDouble() ?? 0.0,
      'quantity': qty,
      'unit_price': price,
      'total_price': qty * price,
      'notes': '',
    });
  }

  Widget _colorSwatch(String? hex) {
    var value = (hex ?? '').replaceFirst('#', '');
    if (value.length == 6) value = 'FF$value';
    final parsed = int.tryParse(value, radix: 16);
    return Container(
      width: 18,
      height: 18,
      decoration: BoxDecoration(
        color: parsed == null ? Colors.grey.shade300 : Color(parsed),
        shape: BoxShape.circle,
        border: Border.all(color: Colors.black26),
      ),
    );
  }

  double _getDefaultPrice(Map<String, dynamic> item) {
    final p =
        item['price'] ??
        item['price_per_sqm'] ??
        item['price_per_sheet'] ??
        0.0;
    return (p as num?)?.toDouble() ?? 0.0;
  }

  String _getUnit() {
    switch (_selectedCategory) {
      case 'Sections':
        return 'barre';
      case 'Accessories':
        return 'pcs';
      case 'Glass':
        return 'm²';
      case 'Joints':
        return 'm';
      case 'ShutterComponents':
        return 'pcs';
      case 'Sheets':
        return 'feuille';
      default:
        return 'pcs';
    }
  }

  TextSpan _highlightedSpan(String text) {
    final query = _searchCtrl.text.trim();
    if (query.isEmpty) return TextSpan(text: text);
    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    var start = 0;
    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index < 0) {
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      spans.add(
        TextSpan(
          text: text.substring(index, index + query.length),
          style: const TextStyle(
            backgroundColor: Color(0xFFFFE082),
            color: Colors.black,
            fontWeight: FontWeight.w800,
          ),
        ),
      );
      start = index + query.length;
    }
    return TextSpan(children: spans);
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final selected = _selectedItem;
    final selectedStock = selected == null
        ? 0.0
        : _stockFor(selected, colorId: _selectedColorId);
    return SizedBox(
      width: 920,
      height: MediaQuery.of(context).size.height * 0.9,
      child: Container(
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 12, 8),
              child: Row(
                children: [
                  const Icon(Icons.inventory_2_outlined, color: _blue),
                  const SizedBox(width: 8),
                  Text(
                    _t('اختر منتجاً'),
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  SizedBox(
                    width: 210,
                    child: DropdownButtonFormField<String>(
                      initialValue: _selectedCategory,
                      isExpanded: true,
                      decoration: InputDecoration(
                        labelText: _t('البحث في'),
                        prefixIcon: const Icon(Icons.tune_rounded),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: _categories
                          .map(
                            (category) => DropdownMenuItem<String>(
                              value: category['id'],
                              child: Text(
                                category['label']!,
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value == null) return;
                        setState(() {
                          _selectedCategory = value;
                          _selectedProfile = '';
                          _selectedItem = null;
                        });
                        _loadItems();
                      },
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: _t('اكتب الاسم أو الرمز للبحث...'),
                        hintStyle: const TextStyle(fontFamily: 'Cairo'),
                        prefixIcon: const Icon(Icons.search, color: _blue),
                        suffixIcon: _searchCtrl.text.isEmpty
                            ? null
                            : IconButton(
                                icon: const Icon(Icons.clear),
                                onPressed: () {
                                  _searchCtrl.clear();
                                  setState(() {
                                    _items = [];
                                    _selectedItem = null;
                                  });
                                },
                              ),
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) {
                        setState(() {});
                        _loadItems();
                      },
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(color: colors.outlineVariant),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: _loading
                      ? const Center(child: CircularProgressIndicator())
                      : _searchCtrl.text.trim().isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.manage_search_rounded,
                                size: 54,
                                color: colors.outlineVariant,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                _t('ابدأ بكتابة اسم المنتج أو رمزه'),
                                style: const TextStyle(fontFamily: 'Cairo'),
                              ),
                            ],
                          ),
                        )
                      : _items.isEmpty
                      ? Center(
                          child: Text(
                            _t('لا توجد نتائج'),
                            style: const TextStyle(fontFamily: 'Cairo'),
                          ),
                        )
                      : ListView.separated(
                          itemCount: _items.length,
                          separatorBuilder: (_, __) => const Divider(height: 1),
                          itemBuilder: (_, i) {
                            final item = _items[i];
                            final name = item['name'] ?? item['type'] ?? '';
                            final code = item['code'] ?? '';
                            final family =
                                item['profile_name']?.toString() ?? '';
                            final series =
                                item['series_name']?.toString() ?? '';
                            final colorName =
                                item['_selected_color_name']?.toString() ?? '';
                            final colorHex = item['_selected_color_hex']
                                ?.toString();
                            final stock = _stockFor(item);
                            final isSelected = identical(item, _selectedItem);
                            return ListTile(
                              selected: isSelected,
                              selectedTileColor: _blue.withOpacity(0.08),
                              leading: colorName.isNotEmpty
                                  ? _colorSwatch(colorHex)
                                  : CircleAvatar(
                                      backgroundColor: _blue.withOpacity(0.1),
                                      child: Text(
                                        _selectedCategory.substring(0, 1),
                                        style: const TextStyle(
                                          color: _blue,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                              title: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: colors.onSurface,
                                    fontFamily: 'Cairo',
                                    fontSize: 13,
                                    fontWeight: FontWeight.w600,
                                  ),
                                  children: [_highlightedSpan(name.toString())],
                                ),
                              ),
                              subtitle: RichText(
                                text: TextSpan(
                                  style: TextStyle(
                                    color: colors.onSurfaceVariant,
                                    fontFamily: 'Cairo',
                                    fontSize: 11,
                                  ),
                                  children: [
                                    _highlightedSpan(
                                      [code, family, series, colorName]
                                          .where(
                                            (value) =>
                                                value.toString().isNotEmpty,
                                          )
                                          .join(' · '),
                                    ),
                                  ],
                                ),
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    _t('المتوفر'),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 9,
                                      color: colors.onSurfaceVariant,
                                    ),
                                  ),
                                  Text(
                                    NumberFormat('#,##0.##').format(stock),
                                    style: TextStyle(
                                      fontFamily: 'Cairo',
                                      fontWeight: FontWeight.bold,
                                      color: stock > 0
                                          ? Colors.green
                                          : Colors.red,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () => _selectItem(item),
                            );
                          },
                        ),
                ),
              ),
            ),
            AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              child: selected == null
                  ? const SizedBox(height: 14)
                  : Container(
                      key: ValueKey('${selected['id']}_$_selectedColorId'),
                      margin: const EdgeInsets.fromLTRB(20, 10, 20, 16),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: colors.surfaceContainerLow,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: colors.outlineVariant),
                      ),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  selected['name'] ?? selected['type'] ?? '',
                                  style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              Text(
                                '${_t('المتوفر')}: ${NumberFormat('#,##0.##').format(selectedStock)} ${_getUnit()}',
                                style: TextStyle(
                                  fontFamily: 'Cairo',
                                  color: selectedStock > 0
                                      ? Colors.green
                                      : Colors.red,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              if (_selectedItemColors.isNotEmpty) ...[
                                Expanded(
                                  flex: 2,
                                  child: DropdownButtonFormField<int>(
                                    initialValue: _selectedColorId,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: _t('اللون'),
                                      border: const OutlineInputBorder(),
                                      isDense: true,
                                    ),
                                    items: _selectedItemColors.map((color) {
                                      final id = (color['id'] as num).toInt();
                                      return DropdownMenuItem<int>(
                                        value: id,
                                        child: Row(
                                          children: [
                                            _colorSwatch(
                                              color['hex_code']?.toString(),
                                            ),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                color['name']?.toString() ?? '',
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }).toList(),
                                    onChanged: (value) async {
                                      if (value == null) return;
                                      final color = _selectedItemColors
                                          .firstWhere(
                                            (entry) =>
                                                (entry['id'] as num).toInt() ==
                                                value,
                                          );
                                      final price = await _resolvePrice(
                                        selected,
                                        colorId: value,
                                      );
                                      if (!mounted) return;
                                      setState(() {
                                        _selectedColorId = value;
                                        _selectedColorName =
                                            color['name']?.toString() ?? '';
                                        _priceCtrl.text = price.toStringAsFixed(
                                          2,
                                        );
                                      });
                                    },
                                  ),
                                ),
                                const SizedBox(width: 10),
                              ],
                              Expanded(
                                child: TextField(
                                  controller: _quantityCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: const [
                                    DecimalTextInputFormatter(decimalDigits: 3),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: _t('الكمية'),
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextField(
                                  controller: _priceCtrl,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                        decimal: true,
                                      ),
                                  inputFormatters: const [
                                    DecimalTextInputFormatter(),
                                  ],
                                  decoration: InputDecoration(
                                    labelText: _t('سعر الوحدة'),
                                    suffixText: 'DA',
                                    border: const OutlineInputBorder(),
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              FilledButton.icon(
                                onPressed: _addSelectedItem,
                                icon: const Icon(
                                  Icons.add_shopping_cart_rounded,
                                ),
                                label: Text(
                                  _t('إضافة'),
                                  style: const TextStyle(fontFamily: 'Cairo'),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
