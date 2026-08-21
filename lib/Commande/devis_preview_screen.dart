import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/devis_builder.dart';
import 'package:database_data/Commande/pdf_invoice_api.dart';

class DevisPreviewScreen extends StatefulWidget {
  final DevisData data;
  final int? deliveryId;
  final bool initialIsLoaded;

  const DevisPreviewScreen({
    super.key,
    required this.data,
    this.deliveryId,
    this.initialIsLoaded = false,
  });

  @override
  State<DevisPreviewScreen> createState() => _DevisPreviewScreenState();
}

class _DevisPreviewScreenState extends State<DevisPreviewScreen> {
  late AppLanguage _invoiceLanguage;
  late DevisData _currentDevisData;
  String _chequeNumber = '';
  Timer? _debounceTimer;
  bool _isLoaded = false;
  static const _blue = Color(0xFF1565C0);
  static const _headerBlue = Color(0xFF1976D2);
  // The visual Devis is already available from DevisData. PDF bytes are
  // prepared in the background and must not block opening the preview.
  bool _isLoading = false;
  Uint8List? _pdfBytes;
  Future<Uint8List?>? _pdfBuildFuture;

  String t(String key) {
    try {
      return Localization.translate(key, _invoiceLanguage);
    } catch (_) {
      return key;
    }
  }

  AppLanguage get lang => _invoiceLanguage;

  DevisData get data => _currentDevisData;
  bool get _isOfficial =>
      data.isProForma ||
      data.documentTitleKey == 'FACTURE_VENTE' ||
      data.documentTitleKey == 'BON_ROUTE';

  String get _documentTitle {
    if (data.isProForma) {
      if (_invoiceLanguage == AppLanguage.french) {
        return 'Facture Proforma';
      } else if (_invoiceLanguage == AppLanguage.english) {
        return 'Proforma Invoice';
      } else {
        return 'فاتورة تقديرية / أولية';
      }
    } else {
      var titleKey = data.documentTitleKey;
      if (titleKey == 'BON_ROUTE') {
        titleKey = 'FACTURE_VENTE';
      }
      if (titleKey == 'BON_CHARGE') {
        if (_invoiceLanguage == AppLanguage.french) {
          return 'Bon d\'expédition / Charge';
        } else if (_invoiceLanguage == AppLanguage.english) {
          return 'Shipping & Delivery Note';
        } else {
          return 'فاتورة / وصل شحن كلي';
        }
      }
      if (titleKey == 'doc_bon_livraison_sans_prix' ||
          titleKey == 'doc_bon_livraison_partiel' ||
          titleKey == 'doc_bon_livraison_partiel_sans_prix') {
        if (_invoiceLanguage == AppLanguage.french) {
          return 'Bon de livraison';
        } else if (_invoiceLanguage == AppLanguage.english) {
          return 'Delivery Note';
        } else {
          return 'وصل تسليم';
        }
      }
      return titleKey != null
          ? t(titleKey)
          : (data.isPartial ? 'DEVIS PARTIEL' : 'DEVIS');
    }
  }

  @override
  void initState() {
    super.initState();
    _currentDevisData = widget.data;
    _chequeNumber = widget.data.chequeNumber;
    _isLoaded = widget.initialIsLoaded;
    _invoiceLanguage = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    _initPdfGeneration();
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPdfGeneration() async {
    if (_pdfBuildFuture != null) return;
    _pdfBuildFuture = _buildPdfBytes(showErrors: false);
    try {
      final bytes = await _pdfBuildFuture;
      if (mounted) {
        setState(() {
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في توليد PDF: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      _pdfBuildFuture = null;
    }
  }

  Future<Uint8List?> _buildPdfBytes({bool showErrors = true}) async {
    try {
      await PdfInvoiceApi.preloadFonts().timeout(const Duration(seconds: 15));
      return await PdfInvoiceApi.buildPdfBytes(
        _currentDevisData,
        overrideLang: _invoiceLanguage,
      ).timeout(const Duration(seconds: 45));
    } catch (e) {
      debugPrint('PDF generation error: $e');
      if (showErrors && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في توليد PDF: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }
  }

  Future<Uint8List?> _ensurePdfBytes() async {
    if (_pdfBytes != null) return _pdfBytes;

    setState(() => _isLoading = true);
    try {
      _pdfBuildFuture ??= _buildPdfBytes();
      var bytes = await _pdfBuildFuture;
      if (bytes == null) {
        _pdfBuildFuture = _buildPdfBytes();
        bytes = await _pdfBuildFuture;
      }
      if (mounted && bytes != null) {
        setState(() => _pdfBytes = bytes);
      }
      return bytes;
    } finally {
      _pdfBuildFuture = null;
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _changeInvoiceLanguage(AppLanguage newLang) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _invoiceLanguage = newLang;
    });

    try {
      final rebuiltData = await DevisBuilder.build(
        order: widget.data.rawOrder ?? {},
        items: widget.data.rawItems ?? [],
        workshop: widget.data.workshop,
        isPartial: widget.data.isPartial,
        hidePrices: widget.data.hidePrices,
        isProForma: widget.data.isProForma,
        documentTitleKey: widget.data.documentTitleKey,
        overrideLang: newLang,
        chequeNumber: _chequeNumber,
      );

      final bytes = await PdfInvoiceApi.buildPdfBytes(
        rebuiltData,
        overrideLang: newLang,
      ).timeout(const Duration(seconds: 45));

      if (mounted) {
        setState(() {
          _currentDevisData = rebuiltData;
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error changing invoice language: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ أثناء تغيير لغة الفاتورة: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _onChequeChanged(String val) {
    if (_debounceTimer?.isActive ?? false) _debounceTimer!.cancel();
    _debounceTimer = Timer(const Duration(milliseconds: 500), () {
      _updateChequeNumber(val);
    });
  }

  Future<void> _updateChequeNumber(String number) async {
    setState(() {
      _chequeNumber = number;
      _isLoading = true;
    });

    try {
      final rebuiltData = await DevisBuilder.build(
        order: widget.data.rawOrder ?? {},
        items: widget.data.rawItems ?? [],
        workshop: widget.data.workshop,
        isPartial: widget.data.isPartial,
        hidePrices: widget.data.hidePrices,
        isProForma: widget.data.isProForma,
        documentTitleKey: widget.data.documentTitleKey,
        overrideLang: _invoiceLanguage,
        chequeNumber: number,
      );

      final bytes = await PdfInvoiceApi.buildPdfBytes(
        rebuiltData,
        overrideLang: _invoiceLanguage,
      );

      if (mounted) {
        setState(() {
          _currentDevisData = rebuiltData;
          _pdfBytes = bytes;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('Error updating cheque number: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Widget _buildLanguageSelector() {
    final isArabic = _invoiceLanguage == AppLanguage.arabic;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          bottom: BorderSide(color: Colors.grey.shade300, width: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  const Icon(Icons.translate, color: _blue, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    _invoiceLanguage == AppLanguage.french
                        ? 'Langue de la facture :'
                        : 'لغة تفاصيل الفاتورة :',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
              Container(
                decoration: BoxDecoration(
                  color: Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    GestureDetector(
                      onTap: () {
                        if (_invoiceLanguage != AppLanguage.arabic) {
                          _changeInvoiceLanguage(AppLanguage.arabic);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: isArabic ? _blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'العربية',
                          style: TextStyle(
                            color: isArabic ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),
                    GestureDetector(
                      onTap: () {
                        if (_invoiceLanguage != AppLanguage.french) {
                          _changeInvoiceLanguage(AppLanguage.french);
                        }
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: !isArabic ? _blue : Colors.transparent,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          'Français',
                          style: TextStyle(
                            color: !isArabic ? Colors.white : Colors.black87,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            fontFamily: 'Cairo',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (_isOfficial) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                const Icon(Icons.payment, color: _blue, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: SizedBox(
                    height: 40,
                    child: TextField(
                      onChanged: _onChequeChanged,
                      decoration: InputDecoration(
                        labelText: _invoiceLanguage == AppLanguage.french
                            ? 'Numéro de chèque'
                            : 'رقم الشيك',
                        labelStyle: const TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: 13,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                      style: const TextStyle(fontSize: 14),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildBonDeChargeScreenBody() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.white70 : Colors.black54;
    final headerBg = isDark ? const Color(0xFF1E293B) : Colors.grey.shade200;
    final clientBg = isDark ? const Color(0xFF0F172A) : Colors.grey.shade100;
    final clientBorder = isDark
        ? const Color(0xFF334155)
        : Colors.grey.shade300;
    final itemBg = isDark ? const Color(0xFF1E293B) : Colors.white;

    final List<Map<String, dynamic>> rows = [];
    int globalIndex = 0;
    for (final item in data.items) {
      for (int i = 0; i < item.quantity; i++) {
        globalIndex++;
        final barcodeVal =
            'CMD-${data.orderId}-D${item.detailId}-W$globalIndex-F';
        final cumTicketNum = data.priorConfirmedWindowsCount + globalIndex;
        rows.add({
          'num': '$globalIndex',
          'cumNum': '#$cumTicketNum',
          'title': item.title,
          'dims': '${item.width} x ${item.height} mm',
          'color': item.color,
          'barcode': barcodeVal,
        });
      }
    }

    final isFr = _invoiceLanguage == AppLanguage.french;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.deliveryId != null) ...[
          Container(
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
            decoration: BoxDecoration(
              color: _isLoaded
                  ? (isDark
                        ? Colors.green.shade900.withValues(alpha: 0.4)
                        : Colors.green.shade100)
                  : (isDark
                        ? Colors.amber.shade900.withValues(alpha: 0.4)
                        : Colors.amber.shade100),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: _isLoaded ? Colors.green : Colors.amber.shade700,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  _isLoaded ? Icons.check_circle : Icons.hourglass_top,
                  color: _isLoaded
                      ? (isDark ? Colors.green.shade300 : Colors.green.shade800)
                      : (isDark
                            ? Colors.amber.shade300
                            : Colors.amber.shade900),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    _isLoaded
                        ? (isFr
                              ? 'Statut: Chargement confirmé ✓'
                              : 'الحالة: تم تأكيد التحميل بنجاح ✓')
                        : (isFr
                              ? 'Statut: Non encore chargé'
                              : 'الحالة: معلق - لم يتم تأكيد التحميل بعد'),
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      fontFamily: 'Cairo',
                      color: _isLoaded
                          ? (isDark
                                ? Colors.green.shade200
                                : Colors.green.shade900)
                          : (isDark
                                ? Colors.amber.shade200
                                : Colors.amber.shade900),
                    ),
                  ),
                ),
                if (!_isLoaded)
                  ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () async {
                      await SqlDatabase().updateCommandeDeliveryIsLoaded(
                        widget.deliveryId!,
                        1,
                      );
                      setState(() {
                        _isLoaded = true;
                      });
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(
                              isFr
                                  ? 'Chargement confirmé avec succès!'
                                  : 'تم تأكيد التحميل وتحديث السجل بنجاح!',
                            ),
                            backgroundColor: Colors.green,
                          ),
                        );
                      }
                    },
                    icon: const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      isFr ? 'Confirmer le chargement' : 'تأكيد التحميل',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontFamily: 'Cairo',
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  data.workshop.name,
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
                if (data.workshop.phone.isNotEmpty)
                  Text(
                    'Tél: ${data.workshop.phone}',
                    style: TextStyle(fontSize: 12, color: subtextColor),
                  ),
              ],
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  isFr ? 'Bon de charge' : 'وصل الشحن',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                    color: _blue,
                    fontFamily: 'Cairo',
                  ),
                ),
                Text(
                  'Date: ${data.orderDate}',
                  style: TextStyle(fontSize: 12, color: subtextColor),
                ),
              ],
            ),
          ],
        ),
        const Divider(height: 20, thickness: 1),

        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: clientBg,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: clientBorder),
          ),
          child: Row(
            children: [
              Text(
                isFr ? 'Client: ' : 'الزبون: ',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  fontFamily: 'Cairo',
                  color: textColor,
                ),
              ),
              Text(
                data.clientName,
                style: TextStyle(
                  fontSize: 14,
                  fontFamily: 'Cairo',
                  color: textColor,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 15),

        Container(
          padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
          decoration: BoxDecoration(
            color: headerBg,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(6)),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 45,
                child: Text(
                  isFr
                      ? 'N°'
                      : _invoiceLanguage == AppLanguage.english
                      ? 'No'
                      : 'رقم',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  isFr
                      ? 'Désignation'
                      : _invoiceLanguage == AppLanguage.english
                      ? 'Item Designation'
                      : 'البيان / النافذة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  isFr
                      ? 'Dimensions'
                      : _invoiceLanguage == AppLanguage.english
                      ? 'Dimensions'
                      : 'المقاسات',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                flex: 2,
                child: Text(
                  isFr
                      ? 'Couleur'
                      : _invoiceLanguage == AppLanguage.english
                      ? 'Color'
                      : 'اللون',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
              Expanded(
                flex: 3,
                child: Text(
                  isFr
                      ? 'Code à barres'
                      : _invoiceLanguage == AppLanguage.english
                      ? 'Barcode'
                      : 'الكود بار',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
        ),

        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: rows.length,
          separatorBuilder: (context, index) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final row = rows[index];
            return Container(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              color: itemBg,
              child: Row(
                children: [
                  SizedBox(
                    width: 45,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          row['num']!,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: textColor,
                          ),
                        ),
                        Text(
                          row['cumNum']!,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.cyanAccent : subtextColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Text(
                      row['title'] ?? '',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                        fontFamily: 'Cairo',
                        color: textColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row['dims']!,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                  Expanded(
                    flex: 2,
                    child: Text(
                      row['color']!,
                      style: TextStyle(fontSize: 13, color: textColor),
                    ),
                  ),
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          Icons.qr_code,
                          size: 20,
                          color: isDark ? Colors.white : Colors.black87,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          row['barcode']!,
                          style: TextStyle(
                            fontSize: 10,
                            color: isDark ? Colors.white70 : subtextColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final isBonDeCharge = data.documentTitleKey == 'BON_CHARGE';

    return Scaffold(
      backgroundColor: isDark
          ? const Color(0xFF121212)
          : const Color(0xFFF3F5F8),
      appBar: AppBar(
        title: Text(
          _documentTitle,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontFamily: 'Cairo',
          ),
        ),
        centerTitle: true,
        backgroundColor: isDark ? const Color(0xFF1E1E1E) : _blue,
        foregroundColor: Colors.white,
        elevation: 1.0,
      ),
      body: Stack(
        children: [
          Column(
            children: [
              _buildLanguageSelector(),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      color: isDark ? const Color(0xFF1E1E1E) : Colors.white,
                      borderRadius: BorderRadius.circular(8),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.06),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (data.documentTitleKey == 'BON_CHARGE') ...[
                          _buildBonDeChargeScreenBody(),
                        ] else ...[
                          _buildTopHeader(),
                          const Divider(height: 28, thickness: 1),
                          _buildParties(),
                          if (_chequeNumber.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Align(
                              alignment: Alignment.centerRight,
                              child: Text(
                                _invoiceLanguage == AppLanguage.french
                                    ? 'N° chèque: $_chequeNumber'
                                    : 'رقم الشيك: $_chequeNumber',
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: _blue,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                          ] else ...[
                            const SizedBox(height: 16),
                          ],
                          _buildTableHeader(),
                          ...data.items.asMap().entries.map(
                            (e) => _buildItemRow(e.key, e.value),
                          ),
                          const SizedBox(height: 18),
                          if (!data.hidePrices) ...[
                            _buildAmountInWords(),
                            const SizedBox(height: 12),
                            _buildTotals(),
                          ] else ...[
                            const SizedBox(height: 12),
                            _buildTotalQuantityPreview(),
                          ],
                          if (_isOfficial && data.workshop.rib.isNotEmpty) ...[
                            const SizedBox(height: 14),
                            Align(
                              alignment: Alignment.centerLeft,
                              child: Text(
                                _invoiceLanguage == AppLanguage.french
                                    ? 'RIB: ${data.workshop.rib}'
                                    : _invoiceLanguage == AppLanguage.english
                                    ? 'RIB: ${data.workshop.rib}'
                                    : 'الحساب البنكي (RIB): ${data.workshop.rib}',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: Colors.black87,
                                  fontFamily: 'Cairo',
                                ),
                              ),
                            ),
                          ],
                          _buildFooter(),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
              _buildBottomActions(context),
            ],
          ),
          if (_isLoading)
            Positioned.fill(
              child: Container(
                color: Colors.black.withValues(alpha: 0.25),
                child: const Center(
                  child: CircularProgressIndicator(
                    valueColor: AlwaysStoppedAnimation<Color>(_blue),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  String _formatDocumentNumber(DevisData data) {
    String prefix = 'DV';
    final key = data.documentTitleKey ?? '';

    if (key == 'BON_CHARGE') {
      prefix = data.isPartial ? 'FCP' : 'FC';
    } else if (key == 'FACTURE_VENTE' || key == 'BON_ROUTE') {
      prefix = 'FV';
    } else if (key == 'doc_devis' || key == 'DEVIS') {
      prefix = data.isPartial ? 'DVP' : 'DV';
    } else if (key == 'DEVIS_PARTIAL') {
      prefix = 'DVP';
    } else if (data.isProForma) {
      prefix = data.isPartial ? 'FPP' : 'FP';
    } else if (key == 'doc_bon_livraison' ||
        key == 'doc_bon_livraison_sans_prix') {
      prefix = 'BL';
    } else if (key == 'doc_bon_livraison_partiel' ||
        key == 'doc_bon_livraison_partiel_sans_prix') {
      prefix = 'BLP';
    } else {
      if (data.isProForma) {
        prefix = 'FP';
      } else {
        prefix = 'DV';
      }
    }

    String year2 = (DateTime.now().year % 100).toString().padLeft(2, '0');
    try {
      final dateStr = data.orderDate;
      final yearMatch = RegExp(r'\b(20\d{2})\b').firstMatch(dateStr);
      if (yearMatch != null) {
        year2 = yearMatch.group(1)!.substring(2);
      } else {
        final any4Digit = RegExp(r'\b(\d{4})\b').firstMatch(dateStr);
        if (any4Digit != null) {
          year2 = any4Digit.group(1)!.substring(2);
        }
      }
    } catch (_) {}

    final seq = data.sequenceNumber > 0
        ? data.sequenceNumber
        : (data.orderId > 0 && data.orderId < 100000
              ? data.orderId
              : (data.orderId % 1000).abs());
    final seqNum = seq.toString().padLeft(3, '0');
    return '$prefix$year2$seqNum';
  }

  Widget _buildTopHeader() {
    final title = _documentTitle;

    Widget? logoWidget;
    if (data.workshop.logoBase64.isNotEmpty) {
      try {
        final imageBytes = base64Decode(data.workshop.logoBase64);
        logoWidget = Image.memory(imageBytes, width: 50, height: 50);
      } catch (_) {}
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            if (logoWidget != null) ...[logoWidget, const SizedBox(width: 10)],
            Text(
              data.workshop.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
                fontFamily: 'Cairo',
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        const Divider(height: 1, thickness: 0.8, color: Colors.black12),
        const SizedBox(height: 8),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: _blue,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _metaLine('N°:', _formatDocumentNumber(data)),
                _metaLine('Date:', data.orderDate),
                if (data.isProForma && data.validUntil.isNotEmpty)
                  _metaLine('Valide jusqu\'au:', data.validUntil),
              ],
            ),
          ],
        ),
      ],
    );
  }

  Widget _metaLine(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: RichText(
        text: TextSpan(
          style: const TextStyle(fontSize: 12, color: Colors.black87),
          children: [
            TextSpan(
              text: '$label ',
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
            TextSpan(text: value),
          ],
        ),
      ),
    );
  }

  Widget _buildParties() {
    final phonePrefix = _invoiceLanguage == AppLanguage.french
        ? 'Tél: '
        : _invoiceLanguage == AppLanguage.english
        ? 'Phone: '
        : 'الهاتف: ';
    final clientIdPrefix = _invoiceLanguage == AppLanguage.french
        ? 'N° Client: '
        : _invoiceLanguage == AppLanguage.english
        ? 'Client ID: '
        : 'رقم الزبون: ';
    final addressPrefix = _invoiceLanguage == AppLanguage.french
        ? 'Adresse: '
        : _invoiceLanguage == AppLanguage.english
        ? 'Address: '
        : 'العنوان: ';

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: _partyBlock('FOURNISSEUR', [
            data.workshop.name,
            if (data.workshop.phone.isNotEmpty)
              '$phonePrefix${data.workshop.phone}',
            if (data.workshop.address.isNotEmpty)
              '$addressPrefix${data.workshop.address}',
            if (_isOfficial) ...[
              if (data.workshop.rc.isNotEmpty) 'RC: ${data.workshop.rc}',
              if (data.workshop.nif.isNotEmpty) 'NIF: ${data.workshop.nif}',
              if (data.workshop.nis.isNotEmpty) 'NIS: ${data.workshop.nis}',
              if (data.workshop.ai.isNotEmpty) 'AI: ${data.workshop.ai}',
            ],
          ]),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: _partyBlock('CLIENT', [
            if (data.clientReference.isNotEmpty)
              '$clientIdPrefix${data.clientReference}',
            data.clientName,
            if (data.clientPhone.isNotEmpty) '$phonePrefix${data.clientPhone}',
            if (data.clientNif.isNotEmpty) 'NIF: ${data.clientNif}',
            if (data.clientNis.isNotEmpty) 'NIS: ${data.clientNis}',
            if (data.clientRc.isNotEmpty) 'RC: ${data.clientRc}',
            if (data.clientAi.isNotEmpty) 'AI: ${data.clientAi}',
          ]),
        ),
      ],
    );
  }

  Widget _partyBlock(String title, List<String> lines) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: Colors.black54,
            letterSpacing: 0.5,
          ),
        ),
        const SizedBox(height: 6),
        ...lines.map(
          (line) => Padding(
            padding: const EdgeInsets.only(bottom: 2),
            child: Text(
              line,
              style: const TextStyle(fontSize: 13, color: Colors.black87),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    final hidePrices = data.hidePrices;
    return Container(
      color: _headerBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          if (!_isOfficial)
            const SizedBox(
              width: 88,
              child: Text('Image', style: _headerStyle),
            ),
          Expanded(
            flex: hidePrices ? 8 : 4,
            child: const Text('Désignation', style: _headerStyle),
          ),
          if (!hidePrices)
            Expanded(
              flex: 2,
              child: Text(
                _isOfficial ? 'P.U. H.T.' : t('Prix Unit.'),
                style: _headerStyle,
                textAlign: TextAlign.end,
              ),
            ),
          const SizedBox(
            width: 38,
            child: Text('Qté', style: _headerStyle, textAlign: TextAlign.end),
          ),
          if (!hidePrices)
            Expanded(
              flex: 2,
              child: Text(
                _isOfficial ? 'TOTAL H.T.' : t('Total'),
                style: _headerStyle,
                textAlign: TextAlign.end,
              ),
            ),
        ],
      ),
    );
  }

  static const _headerStyle = TextStyle(
    color: Colors.white,
    fontWeight: FontWeight.bold,
    fontSize: 12,
  );

  Widget _buildItemRow(int index, DevisLineItem item) {
    final bg = index.isEven ? Colors.white : const Color(0xFFF8FAFC);
    final textColor = item.isReplaced ? Colors.grey.shade500 : Colors.black87;
    final detailColor = item.isReplaced
        ? Colors.grey.shade400
        : Colors.grey.shade800;
    final priceColor = item.isReplaced ? Colors.grey.shade500 : _blue;
    final hidePrices = data.hidePrices;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: bg,
        border: data.documentTitleKey == 'BON_ROUTE'
            ? null
            : Border(bottom: BorderSide(color: Colors.grey.shade300)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          CustomPaint(
            foregroundPainter: item.isReplaced ? CardCrossPainter() : null,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (!_isOfficial) ...[
                  SizedBox(
                    width: 88,
                    height: 88,
                    child: Opacity(
                      opacity: item.isReplaced ? 0.6 : 1.0,
                      child: _buildItemImage(item),
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  flex: hidePrices ? 8 : 4,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        item.title,
                        style: TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                          color: textColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      ...() {
                        if (_isOfficial) {
                          if (_invoiceLanguage == AppLanguage.french) {
                            return [
                              'Largeur: ${item.width} mm | Hauteur: ${item.height} mm',
                            ];
                          } else if (_invoiceLanguage == AppLanguage.english) {
                            return [
                              'Width: ${item.width} mm | Height: ${item.height} mm',
                            ];
                          } else {
                            return [
                              'العرض: ${item.width} مم | الارتفاع: ${item.height} مم',
                            ];
                          }
                        } else {
                          return item.details;
                        }
                      }().map(
                        (d) => _detailRichText(
                          d,
                          style: TextStyle(fontSize: 11, color: detailColor),
                        ),
                      ),
                    ],
                  ),
                ),
                if (!hidePrices)
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${_formatMoney(item.unitPrice)} D.A',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: textColor,
                      ),
                    ),
                  ),
                SizedBox(
                  width: 38,
                  child: Text(
                    '${item.quantity}',
                    textAlign: TextAlign.end,
                    style: TextStyle(fontSize: 12, color: textColor),
                  ),
                ),
                if (!hidePrices)
                  Expanded(
                    flex: 2,
                    child: Text(
                      '${_formatMoney(item.unitPrice * item.quantity)} D.A',
                      textAlign: TextAlign.end,
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: priceColor,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (item.isReplaced && item.replacementReason.isNotEmpty) ...[
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.amber.shade50,
                border: Border.all(color: Colors.amber.shade200),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Colors.amber.shade800,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سبب التعديل: ${item.replacementReason}',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.amber.shade900,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _detailRichText(String text, {required TextStyle style}) {
    final labelStyle = style.copyWith(fontWeight: FontWeight.w700);
    return RichText(
      textDirection: _containsArabic(text)
          ? TextDirection.rtl
          : TextDirection.ltr,
      text: TextSpan(children: _detailTextSpans(text, style, labelStyle)),
    );
  }

  List<TextSpan> _detailTextSpans(
    String text,
    TextStyle normalStyle,
    TextStyle labelStyle,
  ) {
    final spans = <TextSpan>[];
    final parts = text.split('|');
    for (var i = 0; i < parts.length; i++) {
      if (i > 0) {
        spans.add(TextSpan(text: ' | ', style: normalStyle));
      }
      final part = parts[i];
      final colonIndex = part.indexOf(':');
      if (colonIndex > 0) {
        spans.add(
          TextSpan(text: part.substring(0, colonIndex + 1), style: labelStyle),
        );
        spans.add(
          TextSpan(text: part.substring(colonIndex + 1), style: normalStyle),
        );
      } else {
        spans.add(TextSpan(text: part, style: normalStyle));
      }
    }
    return spans;
  }

  bool _containsArabic(String text) {
    return RegExp(r'[\u0600-\u06FF]').hasMatch(text);
  }

  Widget _buildItemImage(DevisLineItem item) {
    final path = item.imagePath;

    if (item.title.contains('Caisson Tunnel') ||
        item.title.contains('Caisson Tunnel') ||
        (path != null && path.contains('caisson_tunnel'))) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(2),
        child: Image.asset(
          'Icon/caisson_tunnel.jpg',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) => Image.asset(
            'assets/Icon/caisson_tunnel.jpg',
            fit: BoxFit.contain,
          ),
        ),
      );
    }

    if (item.title.contains('Moustiquaire') ||
        item.title.contains('موستيكير') ||
        (path != null && path.contains('moustiquaire'))) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(2),
        child: Image.asset(
          'Icon/media.webp',
          fit: BoxFit.contain,
          errorBuilder: (context, error, stackTrace) =>
              Image.asset('assets/Icon/media.webp', fit: BoxFit.contain),
        ),
      );
    }

    if (path != null && path.isNotEmpty && File(path).existsSync()) {
      return Container(
        decoration: BoxDecoration(
          color: Colors.grey.shade50,
          border: Border.all(color: Colors.grey.shade300),
          borderRadius: BorderRadius.circular(4),
        ),
        padding: const EdgeInsets.all(4),
        child: Image.file(File(path), fit: BoxFit.contain),
      );
    }
    return Container(
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        '—',
        style: TextStyle(color: Colors.grey.shade500, fontSize: 18),
      ),
    );
  }

  Widget _buildTotalQuantityPreview() {
    final int totalQty = data.items
        .where((i) => !i.isReplaced)
        .fold(0, (s, i) => s + i.quantity);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            t('Quantité Totale / مجموع الكميات'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
              color: Colors.black87,
            ),
          ),
          Text(
            '$totalQty',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: _blue,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAmountInWords() {
    final note = data.invoiceNote.trim();
    String noteLabel;
    if (_invoiceLanguage == AppLanguage.french) {
      noteLabel = 'Remarque';
    } else if (_invoiceLanguage == AppLanguage.english) {
      noteLabel = 'Note';
    } else {
      noteLabel = 'ملاحظة';
    }
    final noteText = '$noteLabel: $note';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Arrêtée la présente facture à la somme de: ${data.amountInWords}.',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
        if (note.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            noteText,
            textDirection: _containsArabic(noteText)
                ? TextDirection.rtl
                : TextDirection.ltr,
            style: const TextStyle(
              fontSize: 12,
              color: Colors.black87,
              fontWeight: FontWeight.w600,
              fontFamily: 'Cairo',
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildTotals() {
    final bool isOfficial = _isOfficial;
    final totalBrutLabel = isOfficial ? 'TOTAL HT' : t('Total Brut');
    final remiseLabel = isOfficial ? 'REMISE' : t('Remise');
    final netHtLabel = isOfficial ? 'NET HT' : t('Total après remise');
    final tvaLabel = isOfficial
        ? 'TVA'
        : 'TVA (${data.tvaPercent.toStringAsFixed(0)}%)';
    final totalTtcLabel = isOfficial ? 'NET A PAYER' : t('TOTAL TTC');

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _totalRow(totalBrutLabel, data.totalBrut),
            _totalRow(remiseLabel, data.remise),
            _totalRow(netHtLabel, data.totalBeforeTax),
            _totalRow(tvaLabel, data.tvaAmount),
            _totalRow(totalTtcLabel, data.totalTTC, highlight: true),
            _totalRow(t('Montant payé'), data.amountPaid),
          ],
        ),
      ),
    );
  }

  Widget _buildFooter() {
    final isOfficial = _isOfficial;
    if (!isOfficial) return const SizedBox.shrink();

    final parts = <String>[];
    if (data.workshop.name.isNotEmpty) {
      parts.add(data.workshop.name);
    }
    if (data.workshop.address.isNotEmpty) {
      parts.add('Adresse: ${data.workshop.address}');
    }
    if (data.workshop.rc.isNotEmpty) parts.add('RC: ${data.workshop.rc}');
    if (data.workshop.nif.isNotEmpty) parts.add('NIF: ${data.workshop.nif}');
    if (data.workshop.nis.isNotEmpty) parts.add('NIS: ${data.workshop.nis}');
    if (data.workshop.ai.isNotEmpty) parts.add('AI: ${data.workshop.ai}');
    if (data.workshop.phone.isNotEmpty)
      parts.add('Tél: ${data.workshop.phone}');

    if (parts.isEmpty) return const SizedBox.shrink();

    final footerText = parts.join(' | ');

    return Column(
      children: [
        const SizedBox(height: 16),
        const Divider(height: 1, thickness: 0.8, color: Colors.black12),
        const SizedBox(height: 10),
        Text(
          footerText,
          style: const TextStyle(
            fontSize: 9,
            color: Colors.black54,
            fontFamily: 'Cairo',
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _totalRow(String label, double value, {bool highlight = false}) {
    if (highlight) {
      return Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 4),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        color: _headerBlue,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
            Text(
              '${_formatMoney(value)} D.A',
              style: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(fontSize: 12)),
          Text(
            '${_formatMoney(value)} D.A',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final bool ready = !_isLoading;
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ready ? _blue : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: ready ? () => _savePdf(context) : null,
                icon: const Icon(Icons.save, size: 16),
                label: Text(
                  t('حفظ'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ready ? _blue : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: ready ? () => _sharePdf(context) : null,
                icon: const Icon(Icons.share, size: 16),
                label: Text(
                  t('مشاركة'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: ready ? _blue : Colors.grey.shade400,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: ready ? () => _printPdf(context) : null,
                icon: const Icon(Icons.print, size: 16),
                label: Text(
                  t('طباعة'),
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _savePdf(BuildContext context) async {
    // Ask filename
    final defaultFileName = data.clientName.trim().isNotEmpty
        ? data.clientName.trim().replaceAll(RegExp(r'[\\/:*?"<>|]'), '_')
        : 'devis_${data.orderId}';
    final nameController = TextEditingController(text: defaultFileName);
    if (!context.mounted) return;
    final confirmedName = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          t('اسم الملف'),
          style: const TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
          ),
        ),
        content: TextField(
          controller: nameController,
          autofocus: true,
          decoration: InputDecoration(
            labelText: t('ادخل اسم الملف'),
            suffixText: '.pdf',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, null),
            child: Text(
              t('إلغاء'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, nameController.text.trim()),
            child: Text(t('حفظ'), style: const TextStyle(fontFamily: 'Cairo')),
          ),
        ],
      ),
    );

    if (confirmedName == null || confirmedName.isEmpty) return;
    if (!context.mounted) return;

    final bytes = _pdfBytes ?? await _ensurePdfBytes();
    if (bytes == null) return;

    setState(() => _isLoading = true);
    try {
      String filename = confirmedName.toLowerCase().endsWith('.pdf')
          ? confirmedName
          : '$confirmedName.pdf';

      String? finalPath;

      if (Platform.isWindows) {
        // On Windows: try Downloads folder directly first
        try {
          final downloadsDir = await getDownloadsDirectory();
          if (downloadsDir != null) {
            final file = File('${downloadsDir.path}\\$filename');
            await file.writeAsBytes(bytes);
            finalPath = file.path;
          }
        } catch (_) {}

        // Fallback: let user pick location
        if (finalPath == null) {
          final picked = await FilePicker.saveFile(
            dialogTitle: t('حفظ PDF'),
            fileName: filename,
            type: FileType.custom,
            allowedExtensions: ['pdf'],
          );
          if (picked != null) {
            await File(picked).writeAsBytes(bytes);
            finalPath = picked;
          }
        }
      } else {
        // Android/iOS: write to temp then use system dialog
        final tempDir = await getTemporaryDirectory();
        final tempFile = File('${tempDir.path}/$filename');
        await tempFile.writeAsBytes(bytes);
        final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
        finalPath = await FlutterFileDialog.saveFile(params: params);
      }

      if (finalPath != null && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t('تم حفظ PDF بنجاح'),
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            duration: const Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في الحفظ: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    final bytes = _pdfBytes ?? await _ensurePdfBytes();
    if (bytes == null) return;

    setState(() => _isLoading = true);
    try {
      await Printing.layoutPdf(
        onLayout: (_) async => bytes,
        name: 'devis_${data.orderId}.pdf',
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في الطباعة: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    final bytes = _pdfBytes ?? await _ensurePdfBytes();
    if (bytes == null) return;

    setState(() => _isLoading = true);
    try {
      final cleanName = data.clientName.trim().replaceAll(
        RegExp(r'[\\/:*?"<>|]'),
        '_',
      );
      final filename = cleanName.isNotEmpty
          ? '$cleanName.pdf'
          : 'devis_${data.orderId}.pdf';

      if (Platform.isWindows) {
        // On Windows share = save with file picker
        final picked = await FilePicker.saveFile(
          dialogTitle: t('مشاركة / حفظ PDF'),
          fileName: filename,
          type: FileType.custom,
          allowedExtensions: ['pdf'],
        );
        if (picked != null) {
          await File(picked).writeAsBytes(bytes);
          if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  t('تم حفظ PDF بنجاح'),
                  style: const TextStyle(fontFamily: 'Cairo'),
                ),
                duration: const Duration(seconds: 4),
              ),
            );
          }
        }
      } else {
        // Mobile: use system share sheet
        await Printing.sharePdf(bytes: bytes, filename: filename);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ في المشاركة: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  static String _formatMoney(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2);
  }
}

class CardCrossPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red.withValues(alpha: 0.4)
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset.zero, Offset(size.width, size.height), paint);
    canvas.drawLine(Offset(0, size.height), Offset(size.width, 0), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
