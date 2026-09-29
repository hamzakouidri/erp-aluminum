import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../sql_database.dart';
import '../settings/app_settings.dart';
import '../settings/localization.dart';
import '../widgets/resizable_columns_table.dart';
import 'achat_item_picker.dart';

class AchatDetailsScreen extends StatefulWidget {
  final int achatId;
  final String invoiceNumber;
  final String supplierName;
  final SqlDatabase? db;

  const AchatDetailsScreen({
    super.key,
    required this.achatId,
    required this.invoiceNumber,
    required this.supplierName,
    this.db,
  });

  @override
  State<AchatDetailsScreen> createState() => _AchatDetailsScreenState();
}

class _AchatDetailsScreenState extends State<AchatDetailsScreen> {
  late final SqlDatabase _db;
  final _formKey = GlobalKey<FormState>();
  final TextEditingController _invoiceController = TextEditingController();
  final TextEditingController _supplierController = TextEditingController();
  bool _isLoading = true;

  String _t(String key) => Localization.translate(
    key,
    Provider.of<AppSettingsProvider>(context, listen: false).language,
  );
  List<Map<String, dynamic>> _items = [];
  double _itemsTotal = 0.0;
  double _paidAmount = 0.0;
  double _remainingAmount = 0.0;
  String _status = 'Active';
  DateTime _purchaseDate = DateTime.now();
  String? _imagePath;
  String? _pdfPath;

  // حفظ القيم الأصلية للتراجع عند الإلغاء
  String _originalInvoice = '';
  String _originalSupplier = '';

  @override
  void initState() {
    super.initState();
    _db = widget.db ?? SqlDatabase();
    _originalInvoice = widget.invoiceNumber;
    _originalSupplier = widget.supplierName;
    _invoiceController.text = widget.invoiceNumber;
    _supplierController.text = widget.supplierName;
    _loadAchatDetails();
  }

  @override
  void dispose() {
    _invoiceController.dispose();
    _supplierController.dispose();
    super.dispose();
  }

  Future<void> _processInventoryUpdate() async {
    final achat = await _db.readAchatById(widget.achatId);
    int locationId = achat?['location_id'] as int? ?? 1;

    for (var item in _items) {
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final itemId = item['item_id'] as int? ?? 0;
      final itemType = item['item_type'] as String? ?? 'Other';
      final colorId = item['color_id'] as int?;

      if (quantity > 0 && itemId > 0) {
        await _db.updateInventory(
          itemId: itemId,
          itemType: itemType,
          colorId: colorId,
          locationId: locationId,
          quantityChange: quantity,
          transactionType: 'Purchase',
          referenceId: widget.achatId,
        );
      }
    }
  }

  Future<void> _saveAchatDetails() async {
    if (!_formKey.currentState!.validate()) return;
    final newInvoice = _invoiceController.text.trim();
    final newSupplier = _supplierController.text.trim();

    final myDb = await _db.db;
    final existingTx = await myDb!.query(
      'Treasury',
      where: "reference_id = ? AND entity_type = 'Supplier'",
      whereArgs: [widget.achatId],
    );

    DateTime? existingPaymentDate;
    if (existingTx.isNotEmpty) {
      existingPaymentDate = DateTime.tryParse(
        existingTx.first['created_at']?.toString() ?? '',
      );
    }
    final paymentChoice = await _showPaymentOptionDialog(
      initialPaymentDate: existingPaymentDate,
    );
    if (paymentChoice == null) return;

    await _db.updateAchatInfo(widget.achatId, newInvoice, newSupplier);

    final paidAmount = paymentChoice['paid_amount'] as double;
    final remainingAmount = paymentChoice['remaining_amount'] as double;
    final status = paymentChoice['status'] as String;

    final bool wasConfirmed = _status == 'Confirmed';

    await _db.updateAchatPayment(
      widget.achatId,
      paidAmount: paidAmount,
      remainingAmount: remainingAmount,
      status: status,
    );

    if (!wasConfirmed && status == 'Confirmed') {
      await _processInventoryUpdate();
    }

    if (!mounted) return;
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    final achat = await _db.readAchatById(widget.achatId);
    final supplierId = achat?['supplier_id'] as int?;

    if (status == 'Confirmed' && paidAmount > 0) {
      final desc = 'دفع للمورد: $newSupplier - الفاتورة: $newInvoice';
      final recordedBy = settings.userDisplayName;

      if (existingTx.isNotEmpty) {
        final txId = existingTx.first['id'] as int;
        await _db.updateTreasury(
          txId,
          newAmount: paidAmount,
          newDescription: desc,
          newCaisse:
              existingTx.first['caisse_name']?.toString() ?? 'الصندوق الرئيسي',
          newPaymentMethod:
              existingTx.first['payment_method']?.toString() ??
              'نقداً / Espèce',
          newCreatedAt:
              paymentChoice['payment_date']?.toString() ??
              existingTx.first['created_at']?.toString() ??
              DateTime.now().toUtc().toIso8601String(),
        );
      } else {
        await _db.insertTreasury(
          'Décaissement',
          paidAmount,
          desc,
          referenceId: widget.achatId,
          entityType: 'Supplier',
          entityId: supplierId,
          recordedBy: recordedBy,
          createdAt: paymentChoice['payment_date']?.toString(),
        );
      }
    } else {
      if (existingTx.isNotEmpty) {
        final txId = existingTx.first['id'] as int;
        await _db.deleteTreasury(txId);
      }
    }

    await _loadAchatDetails();

    // تحديث القيم الأصلية بعد الحفظ الناجح
    _originalInvoice = newInvoice;
    _originalSupplier = newSupplier;

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'تم حفظ تفاصيل الفاتورة والحالة',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
    }
  }

  Future<Map<String, dynamic>?> _showPaymentOptionDialog({
    DateTime? initialPaymentDate,
  }) async {
    final amountController = TextEditingController();
    String selectedOption = 'confirmed_paid';
    String? errorText;
    DateTime selectedPaymentDate = initialPaymentDate ?? DateTime.now();
    final canChangePaymentDate = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).canChangePaymentDates();

    return showDialog<Map<String, dynamic>>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Text(_t('حفظ التعديلات')),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Align(
                      alignment: Alignment.centerRight,
                      child: Text(
                        _t('اختر نوع الحفظ:'),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    RadioListTile<String>(
                      value: 'confirmed_paid',
                      groupValue: selectedOption,
                      onChanged: (value) => setState(
                        () => selectedOption = value ?? 'confirmed_paid',
                      ),
                      title: Text(_t('مؤكدة ومدفوعة')),
                    ),
                    RadioListTile<String>(
                      value: 'confirmed_only',
                      groupValue: selectedOption,
                      onChanged: (value) => setState(
                        () => selectedOption = value ?? 'confirmed_only',
                      ),
                      title: Text(_t('مؤكدة فقط')),
                    ),
                    RadioListTile<String>(
                      value: 'partial',
                      groupValue: selectedOption,
                      onChanged: (value) =>
                          setState(() => selectedOption = value ?? 'partial'),
                      title: Text(_t('دفع مبلغ معين')),
                    ),
                    if (selectedOption == 'partial') ...[
                      const SizedBox(height: 8),
                      TextField(
                        controller: amountController,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                          signed: false,
                        ),
                        decoration: InputDecoration(
                          labelText: _t('المبلغ المدفوع'),
                          border: const OutlineInputBorder(),
                          errorText: errorText,
                        ),
                      ),
                    ],
                    const SizedBox(height: 12),
                    InkWell(
                      onTap: canChangePaymentDate
                          ? () async {
                              final picked = await showDatePicker(
                                context: dialogContext,
                                initialDate: selectedPaymentDate,
                                firstDate: DateTime(2020),
                                lastDate: DateTime(2030),
                              );
                              if (picked == null) return;
                              setState(() {
                                selectedPaymentDate = DateTime(
                                  picked.year,
                                  picked.month,
                                  picked.day,
                                  selectedPaymentDate.hour,
                                  selectedPaymentDate.minute,
                                );
                              });
                            }
                          : null,
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: _t('تاريخ دفعة المورد'),
                          prefixIcon: const Icon(Icons.calendar_today),
                          suffixIcon: Icon(
                            canChangePaymentDate
                                ? Icons.edit_calendar_outlined
                                : Icons.lock_outline,
                            color: canChangePaymentDate
                                ? Colors.blue
                                : Colors.grey,
                          ),
                          border: const OutlineInputBorder(),
                        ),
                        child: Text(
                          DateFormat('dd/MM/yyyy').format(selectedPaymentDate),
                          style: TextStyle(
                            color: canChangePaymentDate ? null : Colors.grey,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(dialogContext),
                  child: Text(_t('إلغاء')),
                ),
                ElevatedButton(
                  onPressed: () {
                    double newPaid = _paidAmount;
                    double newRemaining = _remainingAmount;
                    String newStatus = _status;

                    if (selectedOption == 'confirmed_paid') {
                      newPaid = _itemsTotal;
                      newRemaining = 0.0;
                      newStatus = 'Confirmed';
                    } else if (selectedOption == 'confirmed_only') {
                      newStatus = 'Confirmed';
                      newPaid = _paidAmount;
                      newRemaining = (_itemsTotal - newPaid).clamp(
                        0.0,
                        double.infinity,
                      );
                    } else {
                      final enteredAmount =
                          double.tryParse(
                            amountController.text.trim().replaceAll(',', '.'),
                          ) ??
                          -1.0;
                      if (enteredAmount <= 0 ||
                          enteredAmount > (_itemsTotal - _paidAmount)) {
                        setState(() {
                          errorText = 'يرجى إدخال مبلغ صالح لا يزيد عن المتبقي';
                        });
                        return;
                      }
                      newPaid = (_paidAmount + enteredAmount).clamp(
                        0.0,
                        _itemsTotal,
                      );
                      newRemaining = (_itemsTotal - newPaid).clamp(
                        0.0,
                        double.infinity,
                      );
                      newStatus = newPaid >= _itemsTotal
                          ? 'Confirmed'
                          : 'Partial';
                    }

                    Navigator.pop(dialogContext, {
                      'paid_amount': newPaid,
                      'remaining_amount': newRemaining,
                      'status': newStatus,
                      'payment_date': selectedPaymentDate.toIso8601String(),
                    });
                  },
                  child: Text(_t('حفظ')),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// التراجع عن التعديلات غير المحفوظة
  void _discardChanges() {
    // التحقق من وجود تغييرات قبل التراجع
    final hasChanges =
        _invoiceController.text.trim() != _originalInvoice ||
        _supplierController.text.trim() != _originalSupplier;

    if (!hasChanges) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_t('لا توجد تعديلات للتراجع عنها')),
          duration: const Duration(seconds: 2),
        ),
      );
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.undo, color: Colors.orange),
            const SizedBox(width: 8),
            Text(_t('تجاهل التعديلات')),
          ],
        ),
        content: Text(
          _t(
            'هل تريد التراجع عن جميع التعديلات غير المحفوظة واستعادة القيم الأصلية؟',
          ),
          textAlign: TextAlign.right,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(_t('لا')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.orange),
            onPressed: () {
              Navigator.pop(ctx);
              setState(() {
                _invoiceController.text = _originalInvoice;
                _supplierController.text = _originalSupplier;
              });
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(_t('تم استعادة القيم الأصلية')),
                  backgroundColor: Colors.orange,
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(
              _t('نعم، تراجع'),
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _loadAchatDetails() async {
    final achat = await _db.readAchatById(widget.achatId);
    final items = await _db.readAchatItems(widget.achatId);
    final itemsTotal = items.fold<double>(0.0, (total, item) {
      final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      final price = (item['price'] as num?)?.toDouble() ?? 0.0;
      return total + (quantity * price);
    });

    if (!mounted) return;
    setState(() {
      _items = items;
      _itemsTotal = itemsTotal;
      _status = achat?['status'] as String? ?? 'Active';
      _paidAmount = (achat?['paid_amount'] as num?)?.toDouble() ?? 0.0;
      _remainingAmount =
          (achat?['remaining_amount'] as num?)?.toDouble() ??
          (_itemsTotal - _paidAmount).clamp(0.0, double.infinity);
      _imagePath = achat?['image_path'] as String?;
      _pdfPath = achat?['pdf_path'] as String?;
      _purchaseDate =
          DateTime.tryParse(achat?['created_at']?.toString() ?? '') ??
          DateTime.now();
      _isLoading = false;
    });
  }

  Future<void> _changePurchaseDate() async {
    final settings = Provider.of<AppSettingsProvider>(context, listen: false);
    if (!settings.canChangePurchaseDates()) return;

    final picked = await showDatePicker(
      context: context,
      initialDate: _purchaseDate,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
    );
    if (picked == null || !mounted) return;

    final nextDate = DateTime(
      picked.year,
      picked.month,
      picked.day,
      _purchaseDate.hour,
      _purchaseDate.minute,
      _purchaseDate.second,
    );
    await _db.updateAchatDate(widget.achatId, nextDate.toIso8601String());
    if (!mounted) return;
    setState(() => _purchaseDate = nextDate);
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(
      SnackBar(content: Text(_t('تم تغيير تاريخ المشتريات'))),
    );
  }

  Future<void> _pickInvoiceImage(ImageSource source) async {
    final XFile? pickedImage = await ImagePicker().pickImage(
      source: source,
      imageQuality: 85,
    );
    if (pickedImage == null) return;

    await _db.updateAchatFiles(widget.achatId, imagePath: pickedImage.path);
    if (!mounted) return;
    setState(() {
      _imagePath = pickedImage.path;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          _t('تم حفظ صورة الفاتورة'),
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Future<void> _showImageSourceOptions() async {
    final source = await showModalBottomSheet<ImageSource>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.camera_alt),
              title: Text(_t('التقاط صورة بالكاميرا')),
              onTap: () => Navigator.pop(context, ImageSource.camera),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library),
              title: Text(_t('اختيار من المعرض')),
              onTap: () => Navigator.pop(context, ImageSource.gallery),
            ),
          ],
        ),
      ),
    );

    if (source != null) {
      await _pickInvoiceImage(source);
    }
  }

  Future<void> _generateInvoicePdf() async {
    final pdf = pw.Document();

    final List<pw.Widget> content = [
      pw.Text(
        _t('فاتورة مشتريات'),
        style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
      ),
      pw.SizedBox(height: 10),
      pw.Text('${_t('رقم الفاتورة:')} ${_invoiceController.text.trim()}'),
      pw.Text('${_t('المورد:')} ${_supplierController.text.trim()}'),
      pw.Text('${_t('معرّف المشتريات:')} ${widget.achatId}'),
      pw.SizedBox(height: 12),
    ];

    if (_imagePath != null && File(_imagePath!).existsSync()) {
      try {
        final imageBytes = File(_imagePath!).readAsBytesSync();
        final invoiceImage = pw.MemoryImage(imageBytes);
        content.addAll([
          pw.Text(_t('صورة الفاتورة المرفقة:')),
          pw.SizedBox(height: 8),
          pw.Center(
            child: pw.Image(
              invoiceImage,
              fit: pw.BoxFit.contain,
              width: 300,
              height: 200,
            ),
          ),
          pw.SizedBox(height: 12),
        ]);
      } catch (_) {
        // Ignore image embed failures and continue without image.
      }
    }

    if (_items.isNotEmpty) {
      content.addAll([
        pw.Text(
          'عناصر الفاتورة:',
          style: pw.TextStyle(fontSize: 16, fontWeight: pw.FontWeight.bold),
        ),
        pw.SizedBox(height: 6),
        pw.Table.fromTextArray(
          headers: ['العنصر', 'النوع', 'الكمية', 'السعر', 'الإجمالي'],
          data: _items.map((item) {
            final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
            final price = (item['price'] as num?)?.toDouble() ?? 0.0;
            return [
              item['item_name'] ?? item['item_code'] ?? '',
              item['item_type'] ?? '',
              quantity.toStringAsFixed(2),
              price.toStringAsFixed(2),
              (quantity * price).toStringAsFixed(2),
            ];
          }).toList(),
        ),
        pw.SizedBox(height: 12),
      ]);
    }

    content.add(
      pw.Text(
        'إجمالي العناصر: ${_formatValue(_itemsTotal)}',
        style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
      ),
    );

    pdf.addPage(
      pw.MultiPage(pageFormat: PdfPageFormat.a4, build: (context) => content),
    );

    final directory = await getApplicationDocumentsDirectory();
    final fileName =
        'invoice_${widget.achatId}_${DateTime.now().millisecondsSinceEpoch}.pdf';
    final file = File('${directory.path}/$fileName');
    await file.writeAsBytes(await pdf.save());

    await _db.updateAchatFiles(widget.achatId, pdfPath: file.path);
    if (!mounted) return;
    setState(() {
      _pdfPath = file.path;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم حفظ الفاتورة كملف PDF',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Future<void> _openPdfFile() async {
    if (_pdfPath == null) return;
    final uri = Uri.file(_pdfPath!);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  String _formatValue(double value) {
    return NumberFormat('#,##0.00', 'en_US').format(value);
  }

  Future<void> _confirmAchat() async {
    if (_status == 'Confirmed') return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'تأكيد الفاتورة',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        content: const Text(
          'هل تريد تأكيد هذه الفاتورة؟ بعد التأكيد ستصبح الفاتورة في حالة مؤكد.',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_t('إلغاء'), style: const TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(_t('تأكيد'), style: const TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    await _db.updateAchatStatus(widget.achatId, 'Confirmed');
    await _processInventoryUpdate();

    if (!mounted) return;
    setState(() {
      _status = 'Confirmed';
    });
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم تأكيد الفاتورة بنجاح',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
      ),
    );
  }

  Future<void> _deleteAchatItem(int itemId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text(
          'حذف عنصر الفاتورة',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        content: const Text(
          'هل تريد حذف هذا العنصر من الفاتورة؟ سيتم خصم كميته من المخزون.',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(_t('إلغاء'), style: const TextStyle(fontFamily: 'Cairo')),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text(
              'حذف',
              style: TextStyle(color: Colors.white, fontFamily: 'Cairo'),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    // deleteAchatItem already handles inventory deduction
    await _db.deleteAchatItem(itemId);
    await _loadAchatDetails();
    await _db.updateAchatTotal(widget.achatId, _itemsTotal);
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'تم حذف العنصر وتحديث المخزون',
          style: TextStyle(fontFamily: 'Cairo'),
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _openItemPicker() async {
    final added = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => AchatItemPicker(achatId: widget.achatId),
      ),
    );
    if (added == true) {
      await _loadAchatDetails();
    }
  }

  Future<void> _returnAchatItem(Map<String, dynamic> item) async {
    final currentQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
    final returnQtyCtrl = TextEditingController();

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: const Text(
            'إرجاع السلعة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'الكمية الحالية: ${_formatValue(currentQty)}',
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: returnQtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _t('كمية الإرجاع'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
          child: Text(_t('إلغاء'), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () async {
                final returnQty =
                    double.tryParse(returnQtyCtrl.text.replaceAll(',', '.')) ??
                    -1.0;
                if (returnQty <= 0 || returnQty > currentQty) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'الكمية يجب أن تكون بين 0 وكمية العنصر الحالية',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                final updatedQty = currentQty - returnQty;
                if (updatedQty <= 0) {
                  await _db.deleteAchatItem(item['id'] as int);
                } else {
                  await _db.updateAchatItem(
                    item['id'] as int,
                    updatedQty,
                    (item['price'] as num?)?.toDouble() ?? 0.0,
                  );
                }

                if (_status == 'Confirmed' || _status == 'Partial Return') {
                  final achat = await _db.readAchatById(widget.achatId);
                  int locationId = achat?['location_id'] as int? ?? 1;
                  try {
                    await _db.updateInventory(
                      itemId: item['item_id'] as int,
                      itemType: item['item_type'] as String? ?? 'Other',
                      colorId: item['color_id'] as int?,
                      locationId: locationId,
                      quantityChange: -returnQty,
                      transactionType: 'Return to Supplier',
                      referenceId: widget.achatId,
                    );
                  } catch (e) {
                    if (!mounted) return;
                    Navigator.pop(dialogContext);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          'لا يمكن إرجاع هذه السلعة: الكمية في المخزون غير كافية أو السلعة غير موجودة.',
                          style: const TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: Colors.red,
                      ),
                    );
                    return;
                  }
                }

                await _loadAchatDetails();
                await _db.updateAchatTotal(widget.achatId, _itemsTotal);

                if (_itemsTotal == 0) {
                  await _db.updateAchatStatus(widget.achatId, 'Returned');
                } else if (_status == 'Confirmed') {
                  await _db.updateAchatStatus(
                    widget.achatId,
                    'Partial Returned',
                  );
                }

                await _loadAchatDetails();
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تم تسجيل إرجاع السلعة بنجاح',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop();
              },
          child: Text(_t('حفظ'), style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSmartReturnDialog() async {
    List<Map<String, dynamic>> returnItemsList = [];
    for (var item in _items) {
      double q = (item['quantity'] as num?)?.toDouble() ?? 0.0;
      if (q > 0) {
        returnItemsList.add({
          'id': item['id'],
          'item_id': item['item_id'],
          'item_type': item['item_type'],
          'color_id': item['color_id'],
          'item_name': item['item_name'] ?? item['item_code'] ?? '',
          'currentQty': q,
          'price': (item['price'] as num?)?.toDouble() ?? 0.0,
          'returnQty': 0.0,
          'selected': false,
        });
      }
    }

    if (returnItemsList.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'لا توجد عناصر للإرجاع',
            style: TextStyle(fontFamily: 'Cairo'),
          ),
        ),
      );
      return;
    }

    final refundCtrl = TextEditingController();

    await showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setStateSB) {
            double totalRefundEstimation = 0.0;
            for (var r in returnItemsList) {
              if (r['selected']) {
                totalRefundEstimation += r['returnQty'] * r['price'];
              }
            }

            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(15),
              ),
              title: const Text(
                'إرجاع ذكي לפاتورة (Retour)',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  color: Colors.orange,
                ),
              ),
              content: SizedBox(
                width: double.maxFinite,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text(
                        'حدد العناصر والكميات التي تود إرجاعها للمورد:',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      const SizedBox(height: 10),
                      ...returnItemsList.map((r) {
                        return CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          controlAffinity: ListTileControlAffinity.leading,
                          value: r['selected'],
                          title: Text(
                            r['item_name'],
                            style: const TextStyle(
                              fontFamily: 'Cairo',
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          subtitle: r['selected']
                              ? Row(
                                  children: [
                                    if (_status == 'Confirmed' ||
                                        _status == 'Partial Returned') ...[
                                      const SizedBox(height: 16),
                                      ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.orange,
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                        ),
                                        onPressed: _showSmartReturnDialog,
                                        icon: const Icon(
                                          Icons.keyboard_return,
                                          color: Colors.white,
                                        ),
                                        label: const Text(
                                          'إرجاع سلع الفاتورة (Retour)',
                                          style: TextStyle(
                                            fontFamily: 'Cairo',
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                      ),
                                    ],
                                    const SizedBox(height: 16),
                                    Expanded(
                                      child: TextFormField(
                                        initialValue: r['returnQty'] == 0
                                            ? r['currentQty'].toString()
                                            : r['returnQty'].toString(),
                                        keyboardType:
                                            const TextInputType.numberWithOptions(
                                              decimal: true,
                                            ),
                                        decoration: InputDecoration(
                                          labelText: _t('كمية الإرجاع'),
                                          isDense: true,
                                        ),
                                        onChanged: (val) {
                                          double? v = double.tryParse(
                                            val.replaceAll(',', '.'),
                                          );
                                          if (v != null &&
                                              v >= 0 &&
                                              v <= r['currentQty']) {
                                            setStateSB(() {
                                              r['returnQty'] = v;
                                            });
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Text(
                                      'من أصل ${r['currentQty']}',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        color: Colors.grey,
                                      ),
                                    ),
                                  ],
                                )
                              : Text(
                                  'الكمية المتوفرة: ${r['currentQty']} (${r['price']} DZD/الوحدة)',
                                  style: const TextStyle(fontSize: 12),
                                ),
                          onChanged: (val) {
                            setStateSB(() {
                              r['selected'] = val ?? false;
                              if (r['selected'] && r['returnQty'] == 0) {
                                r['returnQty'] = r['currentQty'];
                              }
                            });
                          },
                        );
                      }).toList(),
                      const Divider(),
                      const SizedBox(height: 10),
                      Text(
                        'إجمالي قيمة الإرجاع المقدرة: ${_formatValue(totalRefundEstimation)} DZD',
                        style: const TextStyle(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.bold,
                          color: Colors.blue,
                        ),
                      ),
                      const SizedBox(height: 15),
                      TextFormField(
                        controller: refundCtrl,
                        keyboardType: const TextInputType.numberWithOptions(
                          decimal: true,
                        ),
                        decoration: InputDecoration(
                          labelText: _t(
                            'المبلغ المسترجع من المورد (نقداً أو كدين)',
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          hintText: '${_t('مثال:')} $totalRefundEstimation',
                        ),
                      ),
                      const SizedBox(height: 5),
                      Text(
                        _t('سيتم تسجيل هذا المبلغ في الخزينة كمداخيل.'),
                        style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text(
                    'إلغاء',
                    style: TextStyle(fontFamily: 'Cairo'),
                  ),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.orange,
                  ),
                  onPressed: () async {
                    List<Map<String, dynamic>> itemsToReturn = returnItemsList
                        .where((e) => e['selected'] && e['returnQty'] > 0)
                        .toList();
                    if (itemsToReturn.isEmpty) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'الرجاء تحديد عنصر واحد على الأقل وتحديد كمية أكبر من صفر',
                            style: TextStyle(fontFamily: 'Cairo'),
                          ),
                          backgroundColor: Colors.red,
                        ),
                      );
                      return;
                    }
                    double refunded =
                        double.tryParse(
                          refundCtrl.text.trim().replaceAll(',', '.'),
                        ) ??
                        0.0;

                    Navigator.pop(ctx);

                    await _db.returnAchatInvoice(
                      widget.achatId,
                      itemsToReturn,
                      refunded,
                    );

                    if (_status == 'Confirmed' || _status == 'Partial Return') {
                      final achat = await _db.readAchatById(widget.achatId);
                      int locationId = achat?['location_id'] as int? ?? 1;
                      for (var rItem in itemsToReturn) {
                        await _db.updateInventory(
                          itemId: rItem['item_id'] as int? ?? 0,
                          itemType: rItem['item_type'] as String? ?? 'Other',
                          colorId: rItem['color_id'] as int?,
                          locationId: locationId,
                          quantityChange: -(rItem['returnQty'] as num)
                              .toDouble(),
                          transactionType: 'Return to Supplier',
                          referenceId: widget.achatId,
                        );
                      }
                    }

                    await _loadAchatDetails();
                    if (!mounted) return;
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'تم إرجاع العناصر وتحديث الفاتورة بنجاح',
                          style: TextStyle(fontFamily: 'Cairo'),
                        ),
                        backgroundColor: Colors.green,
                      ),
                    );
                  },
                  child: const Text(
                    'تأكيد الإرجاع',
                    style: TextStyle(fontFamily: 'Cairo', color: Colors.white),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _editAchatItem(Map<String, dynamic> item) async {
    final codeCtrl = TextEditingController(
      text: item['item_code']?.toString() ?? '',
    );
    final nameCtrl = TextEditingController(
      text: item['item_name']?.toString() ?? '',
    );
    final qtyCtrl = TextEditingController(
      text: (item['quantity'] as num?)?.toString() ?? '0',
    );
    final priceCtrl = TextEditingController(
      text: (item['price'] as num?)?.toString() ?? '0',
    );

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
          title: Text(
            'تعديل: ${item['item_name'] ?? item['item_code'] ?? 'عنصر'}',
            style: const TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameCtrl,
                decoration: InputDecoration(
                  labelText: _t('اسم العنصر'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: codeCtrl,
                decoration: InputDecoration(
                  labelText: _t('الكود / القياس'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: qtyCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _t('الكمية'),
                  border: const OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: priceCtrl,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: _t('سعر الوحدة'),
                  border: const OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
          child: Text(_t('إلغاء'), style: const TextStyle(fontFamily: 'Cairo')),
            ),
            ElevatedButton(
              onPressed: () async {
                final newQty =
                    double.tryParse(qtyCtrl.text.replaceAll(',', '.')) ?? 0.0;
                final newPrice =
                    double.tryParse(priceCtrl.text.replaceAll(',', '.')) ?? 0.0;
                final newName = nameCtrl.text.trim();
                final newCode = codeCtrl.text.trim();
                if (newName.isEmpty ||
                    newCode.isEmpty ||
                    newQty <= 0 ||
                    newPrice < 0) {
                  if (!mounted) return;
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text(
                        'الاسم والكود مطلوبان، والكمية يجب أن تكون أكبر من 0 والسعر لا يمكن أن يكون سالباً',
                        style: TextStyle(fontFamily: 'Cairo'),
                      ),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }

                // حساب فارق الكمية وتحديث المخزون
                final oldQty = (item['quantity'] as num?)?.toDouble() ?? 0.0;
                final qtyDiff = newQty - oldQty;
                if (qtyDiff != 0) {
                  final achat = await _db.readAchatById(widget.achatId);
                  final locationId = achat?['location_id'] as int? ?? 1;
                  await _db.updateInventory(
                    itemId: item['item_id'] as int,
                    itemType: item['item_type'] as String,
                    colorId: item['color_id'] as int?,
                    locationId: locationId,
                    quantityChange: qtyDiff,
                    transactionType: 'Purchase Edit',
                    referenceId: widget.achatId,
                  );
                }

                await _db.updateAchatItem(
                  item['id'] as int,
                  newQty,
                  newPrice,
                  itemCode: newCode,
                  itemName: newName,
                );
                await _loadAchatDetails();
                await _db.updateAchatTotal(widget.achatId, _itemsTotal);
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text(
                      'تم تحديث الكمية والسعر والمخزون',
                      style: TextStyle(fontFamily: 'Cairo'),
                    ),
                    backgroundColor: Colors.green,
                  ),
                );
                Navigator.of(context).pop();
              },
          child: Text(_t('حفظ'), style: const TextStyle(fontFamily: 'Cairo')),
            ),
          ],
        );
      },
    );
  }

  bool _isGlassAchatItem(Map<String, dynamic> item) {
    final type = item['item_type']?.toString().trim().toLowerCase() ?? '';
    final text = '${item['item_code'] ?? ''} ${item['item_name'] ?? ''}'
        .toLowerCase();
    return type == 'glass' ||
        text.contains('زجاج') ||
        text.contains('glass') ||
        text.contains('vitrage');
  }

  _GlassAchatDimensions? _glassDimensionsFor(Map<String, dynamic> item) {
    if (!_isGlassAchatItem(item)) return null;
    final text = '${item['item_code'] ?? ''} ${item['item_name'] ?? ''}';
    final match = RegExp(
      r'(?:GL-)?(\d{2,5}(?:[.,]\d+)?)\s*[xX×]\s*(\d{2,5}(?:[.,]\d+)?)',
    ).firstMatch(text);
    if (match == null) return null;
    final width = double.tryParse(match.group(1)!.replaceAll(',', '.'));
    final height = double.tryParse(match.group(2)!.replaceAll(',', '.'));
    if (width == null || height == null || width <= 0 || height <= 0) {
      return null;
    }
    final lower = text.toLowerCase();
    return _GlassAchatDimensions(
      width: width,
      height: height,
      hasDecor:
          lower.contains('ديكور') ||
          lower.contains('decor') ||
          lower.contains('décor'),
    );
  }

  Widget _buildGlassAchatPreview(Map<String, dynamic> item) {
    final dimensions = _glassDimensionsFor(item);
    if (dimensions == null) {
      return const Icon(Icons.inventory_2_outlined, color: Colors.grey);
    }
    return SizedBox(
      width: 86,
      height: 58,
      child: CustomPaint(painter: _GlassAchatSketchPainter(dimensions)),
    );
  }

  Widget _buildAchatItemsDesktopTable(bool canEditInvoice, AppLanguage lang) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final headerStyle = const TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.bold,
      fontSize: 12,
      fontFamily: 'Cairo',
    );

    return ResizableColumnsTable(
      key: ValueKey('achat-items-${widget.achatId}-${_items.length}'),
      persistenceKey: 'purchase_items',
      headerColor: isDark ? Colors.grey.shade900 : Colors.blueGrey.shade800,
      borderColor: isDark ? Colors.grey.shade800 : Colors.grey.shade300,
      rowColor: isDark ? const Color(0xFF171721) : Colors.white,
      headerMinHeight: 42,
      rowMinHeight: 52,
      cellPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      columns: [
        ResizableTableColumn(
          id: 'preview',
          label: Text(
            Localization.translate('الرسم', lang),
            style: headerStyle,
          ),
          initialWidth: 96,
          minWidth: 80,
          maxWidth: 150,
          alignment: Alignment.center,
        ),
        ResizableTableColumn(
          id: 'name',
          label: Text(
            Localization.translate('Libellé / Description', lang),
            style: headerStyle,
          ),
          initialWidth: 340,
          minWidth: 220,
          maxWidth: 620,
        ),
        ResizableTableColumn(
          id: 'type',
          label: Text(
            Localization.translate('النوع', lang),
            style: headerStyle,
          ),
          initialWidth: 150,
          minWidth: 110,
          maxWidth: 260,
        ),
        ResizableTableColumn(
          id: 'color',
          label: Text(
            Localization.translate('اللون', lang),
            style: headerStyle,
          ),
          initialWidth: 150,
          minWidth: 100,
          maxWidth: 260,
        ),
        ResizableTableColumn(
          id: 'quantity',
          label: Text(
            Localization.translate('الكمية', lang),
            style: headerStyle,
          ),
          initialWidth: 120,
          minWidth: 90,
          maxWidth: 200,
        ),
        ResizableTableColumn(
          id: 'price',
          label: Text(
            Localization.translate('سعر الوحدة', lang),
            style: headerStyle,
          ),
          initialWidth: 130,
          minWidth: 100,
          maxWidth: 220,
        ),
        ResizableTableColumn(
          id: 'total',
          label: Text(
            Localization.translate('الإجمالي', lang),
            style: headerStyle,
          ),
          initialWidth: 140,
          minWidth: 110,
          maxWidth: 240,
        ),
        ResizableTableColumn(
          id: 'actions',
          label: Text(
            Localization.translate('إجراء', lang),
            style: headerStyle,
          ),
          initialWidth: 130,
          minWidth: 110,
          maxWidth: 180,
          alignment: Alignment.center,
        ),
      ],
      rows: _items.map((item) {
        final quantity = (item['quantity'] as num?)?.toDouble() ?? 0.0;
        final price = (item['price'] as num?)?.toDouble() ?? 0.0;
        final lineTotal = quantity * price;
        return ResizableTableRow(
          cells: [
            _buildGlassAchatPreview(item),
            _achatTableCell(
              Localization.translate(
                item['item_name'] ?? item['item_code'] ?? 'عنصر',
                lang,
              ),
              isDark,
              fontWeight: FontWeight.w700,
              maxLines: 2,
            ),
            _achatTableCell(
              Localization.translate(item['item_type'] ?? '', lang),
              isDark,
            ),
            _achatTableCell(
              item['color_id'] == null
                  ? '-'
                  : Localization.translate(item['color_name'] ?? 'مجهول', lang),
              isDark,
            ),
            _achatTableCell(_formatValue(quantity), isDark),
            _achatTableCell('${_formatValue(price)} DZD', isDark),
            _achatTableCell(
              '${_formatValue(lineTotal)} DZD',
              isDark,
              fontWeight: FontWeight.w700,
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  tooltip: Localization.translate('تعديل', lang),
                  onPressed: canEditInvoice ? () => _editAchatItem(item) : null,
                  icon: const Icon(Icons.edit, size: 19),
                ),
                IconButton(
                  tooltip: Localization.translate('حذف', lang),
                  onPressed: _status == 'Confirmed'
                      ? null
                      : () => _deleteAchatItem(item['id'] as int),
                  icon: const Icon(Icons.delete_outline, size: 19),
                ),
              ],
            ),
          ],
        );
      }).toList(),
    );
  }

  Widget _achatTableCell(
    String text,
    bool isDark, {
    FontWeight fontWeight = FontWeight.w500,
    int maxLines = 1,
  }) {
    return Text(
      text,
      maxLines: maxLines,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: isDark ? Colors.white70 : Colors.grey.shade800,
        fontFamily: 'Cairo',
        fontSize: 12,
        fontWeight: fontWeight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final canReturnItems = true; // الإرجاع متاح للجميع
    final canEditInvoice =
        _status != 'Confirmed' ||
        settings.isManager; // التعديل بعد التأكيد فقط للمديرين
    final canChangePurchaseDate = settings.canChangePurchaseDates();
    final statusText = _status == 'Confirmed'
        ? Localization.translate('مؤكدة', lang)
        : _status == 'Returned'
        ? Localization.translate('مسترجعة', lang)
        : _status == 'Partial Returned'
        ? Localization.translate('جزئياً مسترجعة', lang)
        : Localization.translate(_status, lang);
    final statusColor = _status == 'Confirmed' || _status == 'Returned'
        ? Colors.green
        : Colors.orange;
    return Scaffold(
      appBar: AppBar(
        title: Text(Localization.translate('تفاصيل المشتريات', lang)),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Card(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Form(
                            key: _formKey,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                TextFormField(
                                  controller: _invoiceController,
                                  enabled: canEditInvoice,
                                  decoration: InputDecoration(
                                    labelText: Localization.translate(
                                      'رقم الفاتورة',
                                      lang,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? Localization.translate(
                                          'يرجى إدخال رقم الفاتورة',
                                          lang,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                TextFormField(
                                  controller: _supplierController,
                                  enabled: canEditInvoice,
                                  decoration: InputDecoration(
                                    labelText: Localization.translate(
                                      'المورد',
                                      lang,
                                    ),
                                    border: const OutlineInputBorder(),
                                  ),
                                  validator: (value) =>
                                      (value == null || value.trim().isEmpty)
                                      ? Localization.translate(
                                          'يرجى إدخال اسم المورد',
                                          lang,
                                        )
                                      : null,
                                ),
                                const SizedBox(height: 12),
                                InkWell(
                                  onTap: canChangePurchaseDate
                                      ? _changePurchaseDate
                                      : null,
                                  child: InputDecorator(
                                    decoration: InputDecoration(
                                      labelText: Localization.translate(
                                        'تاريخ المشتريات',
                                        lang,
                                      ),
                                      prefixIcon: const Icon(
                                        Icons.calendar_today,
                                      ),
                                      suffixIcon: Icon(
                                        canChangePurchaseDate
                                            ? Icons.edit_calendar_outlined
                                            : Icons.lock_outline,
                                        color: canChangePurchaseDate
                                            ? Colors.blue
                                            : Colors.grey,
                                      ),
                                      border: const OutlineInputBorder(),
                                    ),
                                    child: Text(
                                      DateFormat(
                                        'dd/MM/yyyy',
                                      ).format(_purchaseDate),
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF2563EB,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                        ),
                                        onPressed: canEditInvoice
                                            ? _saveAchatDetails
                                            : null,
                                        child: Text(
                                          Localization.translate(
                                            'حفظ التعديلات',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        style: ElevatedButton.styleFrom(
                                          backgroundColor: const Color(
                                            0xFF10B981,
                                          ),
                                          shape: RoundedRectangleBorder(
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          minimumSize: const Size.fromHeight(
                                            48,
                                          ),
                                        ),
                                        onPressed: canEditInvoice
                                            ? _openItemPicker
                                            : null,
                                        icon: const Icon(Icons.add),
                                        label: Text(
                                          Localization.translate(
                                            'إضافة عناصر',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontFamily: 'Cairo',
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 8),
                                if (canEditInvoice)
                                  SizedBox(
                                    width: double.infinity,
                                    height: 44,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: Colors.orange.shade700,
                                        side: BorderSide(
                                          color: Colors.orange.shade400,
                                          width: 1.5,
                                        ),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                      ),
                                      onPressed: _discardChanges,
                                      icon: const Icon(Icons.undo, size: 18),
                                      label: Text(
                                        Localization.translate(
                                          'تراجع عن التعديلات',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontFamily: 'Cairo',
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              if (_imagePath != null || _pdfPath != null) ...[
                                Container(
                                  padding: const EdgeInsets.all(12.0),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey.shade900
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      if (_imagePath != null) ...[
                                        Text(
                                          Localization.translate(
                                            'صورة الفاتورة المرفقة',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 8),
                                        ClipRRect(
                                          borderRadius: BorderRadius.circular(
                                            12,
                                          ),
                                          child: Image.file(
                                            File(_imagePath!),
                                            height: 140,
                                            width: double.infinity,
                                            fit: BoxFit.cover,
                                          ),
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      if (_pdfPath != null) ...[
                                        Text(
                                          Localization.translate(
                                            'ملف PDF محفوظ',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                _pdfPath!.split('/').last,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            TextButton(
                                              onPressed: _openPdfFile,
                                              child: Text(
                                                Localization.translate(
                                                  'فتح',
                                                  lang,
                                                ),
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 12),
                                      ],
                                      Row(
                                        children: [
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed:
                                                  _showImageSourceOptions,
                                              icon: const Icon(Icons.photo),
                                              label: Text(
                                                Localization.translate(
                                                  'إرفاق صورة',
                                                  lang,
                                                ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: ElevatedButton.icon(
                                              onPressed: _generateInvoicePdf,
                                              icon: const Icon(
                                                Icons.picture_as_pdf,
                                              ),
                                              label: Text(
                                                Localization.translate(
                                                  'حفظ PDF',
                                                  lang,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 16),
                              ],
                              if (_imagePath == null && _pdfPath == null) ...[
                                Row(
                                  children: [
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _showImageSourceOptions,
                                        icon: const Icon(Icons.photo),
                                        label: Text(
                                          Localization.translate(
                                            'إرفاق صورة',
                                            lang,
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: ElevatedButton.icon(
                                        onPressed: _generateInvoicePdf,
                                        icon: const Icon(Icons.picture_as_pdf),
                                        label: Text(
                                          Localization.translate(
                                            'حفظ PDF',
                                            lang,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 16),
                              ],
                              Card(
                                margin: const EdgeInsets.only(bottom: 16),
                                child: Padding(
                                  padding: const EdgeInsets.all(14.0),
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        '${Localization.translate('الحالة: ', lang)}$statusText',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: statusColor,
                                        ),
                                      ),
                                      const SizedBox(height: 12),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Text(
                                              '${Localization.translate('إجمالي العناصر: ', lang)}${_formatValue(_itemsTotal)}',
                                              style: const TextStyle(
                                                fontSize: 14,
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Text(
                                        '${Localization.translate('المدفوع: ', lang)}${_formatValue(_paidAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                      Text(
                                        '${Localization.translate('المتبقي: ', lang)}${_formatValue(_remainingAmount)}',
                                        style: const TextStyle(fontSize: 14),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              if (_items.isEmpty) ...[
                                Container(
                                  height: 120,
                                  padding: const EdgeInsets.all(16.0),
                                  decoration: BoxDecoration(
                                    color:
                                        Theme.of(context).brightness ==
                                            Brightness.dark
                                        ? Colors.grey.shade900
                                        : Colors.grey.shade100,
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Center(
                                    child: Text(
                                      Localization.translate(
                                        'لا توجد عناصر مضافة بعد.',
                                        lang,
                                      ),
                                    ),
                                  ),
                                ),
                              ] else if (MediaQuery.sizeOf(context).width >=
                                  900) ...[
                                _buildAchatItemsDesktopTable(
                                  canEditInvoice,
                                  lang,
                                ),
                              ] else
                                ..._items.map((item) {
                                  final quantity =
                                      (item['quantity'] as num?)?.toDouble() ??
                                      0.0;
                                  final price =
                                      (item['price'] as num?)?.toDouble() ??
                                      0.0;
                                  final lineTotal = quantity * price;
                                  return Padding(
                                    padding: const EdgeInsets.only(
                                      bottom: 12.0,
                                    ),
                                    child: Card(
                                      child: Padding(
                                        padding: const EdgeInsets.all(14.0),
                                        child: Column(
                                          crossAxisAlignment:
                                              CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              '${Localization.translate(item['item_name'] ?? item['item_code'] ?? 'عنصر', lang)}',
                                              style: const TextStyle(
                                                fontSize: 15,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                            if (_glassDimensionsFor(item) !=
                                                null) ...[
                                              const SizedBox(height: 8),
                                              Align(
                                                alignment: AlignmentDirectional
                                                    .centerStart,
                                                child: _buildGlassAchatPreview(
                                                  item,
                                                ),
                                              ),
                                            ],
                                            const SizedBox(height: 8),
                                            Text(
                                              '${Localization.translate('النوع: ', lang)}${Localization.translate(item['item_type'] ?? '', lang)}',
                                            ),
                                            if (item['color_id'] != null)
                                              Text(
                                                '${Localization.translate('اللون: ', lang)}${Localization.translate(item['color_name'] ?? 'مجهول', lang)}',
                                                style: const TextStyle(
                                                  color: Colors.blueGrey,
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            Text(
                                              '${Localization.translate('الكمية: ', lang)}${_formatValue(quantity)}',
                                            ),
                                            Text(
                                              '${Localization.translate('سعر الوحدة: ', lang)}${_formatValue(price)}',
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              '${Localization.translate('الإجمالي: ', lang)}${_formatValue(lineTotal)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                            const SizedBox(height: 12),
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                OutlinedButton.icon(
                                                  onPressed: canEditInvoice
                                                      ? () =>
                                                            _editAchatItem(item)
                                                      : null,
                                                  icon: const Icon(
                                                    Icons.edit,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    Localization.translate(
                                                      'تعديل',
                                                      lang,
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),

                                                OutlinedButton.icon(
                                                  onPressed:
                                                      _status == 'Confirmed'
                                                      ? null
                                                      : () => _deleteAchatItem(
                                                          item['id'] as int,
                                                        ),
                                                  icon: const Icon(
                                                    Icons.delete_outline,
                                                    size: 18,
                                                  ),
                                                  label: Text(
                                                    Localization.translate(
                                                      'حذف',
                                                      lang,
                                                    ),
                                                    style: const TextStyle(
                                                      fontFamily: 'Cairo',
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  );
                                }).toList(),
                              const SizedBox(height: 16),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _GlassAchatDimensions {
  const _GlassAchatDimensions({
    required this.width,
    required this.height,
    required this.hasDecor,
  });

  final double width;
  final double height;
  final bool hasDecor;
}

class _GlassAchatSketchPainter extends CustomPainter {
  const _GlassAchatSketchPainter(this.dimensions);

  final _GlassAchatDimensions dimensions;

  @override
  void paint(Canvas canvas, Size size) {
    final stroke = Paint()
      ..color = const Color(0xFF0891B2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;
    final fill = Paint()
      ..color = const Color(0xFF67E8F9).withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final decorPaint = Paint()
      ..color = const Color(0xFFF59E0B)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1;

    final available = Size(size.width - 4, size.height - 16);
    final ratio = dimensions.width / dimensions.height;
    var drawWidth = available.width;
    var drawHeight = drawWidth / ratio;
    if (drawHeight > available.height) {
      drawHeight = available.height;
      drawWidth = drawHeight * ratio;
    }
    final rect = Rect.fromLTWH(
      (size.width - drawWidth) / 2,
      1,
      drawWidth,
      drawHeight,
    );

    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      fill,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(rect, const Radius.circular(3)),
      stroke,
    );

    if (dimensions.hasDecor) {
      canvas.drawLine(rect.centerLeft, rect.centerRight, decorPaint);
      canvas.drawLine(rect.topCenter, rect.bottomCenter, decorPaint);
      canvas.drawCircle(rect.center, 3.5, decorPaint);
    }

    final paragraphStyle = ui.ParagraphStyle(
      textAlign: TextAlign.center,
      fontSize: 9,
      maxLines: 1,
    );
    final textStyle = TextStyle(
      color: const Color(0xFF0F172A),
      fontSize: 9,
      fontWeight: FontWeight.w700,
    );
    final builder = ui.ParagraphBuilder(paragraphStyle)
      ..pushStyle(textStyle.getTextStyle())
      ..addText('${dimensions.width.round()} × ${dimensions.height.round()}');
    final paragraph = builder.build()
      ..layout(ui.ParagraphConstraints(width: size.width));
    canvas.drawParagraph(paragraph, Offset(0, size.height - 13));
  }

  @override
  bool shouldRepaint(covariant _GlassAchatSketchPainter oldDelegate) =>
      oldDelegate.dimensions.width != dimensions.width ||
      oldDelegate.dimensions.height != dimensions.height ||
      oldDelegate.dimensions.hasDecor != dimensions.hasDecor;
}
