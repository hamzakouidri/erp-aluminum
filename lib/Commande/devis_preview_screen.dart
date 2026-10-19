import 'dart:io';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:database_data/widgets/app_material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:flutter_file_dialog/flutter_file_dialog.dart';
import 'package:file_picker/file_picker.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/services/cloud_sync_service.dart';
import 'package:database_data/services/share_filename_utils.dart';
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
  int? _activeDeliveryId;
  String? _activeDeliveryDate;
  int _imageMode = 0; // 0=Latérale, 1=Sous-prix, 2=Pleine largeur
  // 0 = سعر الورشة (Standard), 1 = سعر المقاول (-10%), 2 = سعر المشروع (-18%)
  int _pricingTier = 0;
  static const _blue = Color(0xFF1565C0);
  static const _headerBlue = Color(0xFF1976D2);

  double get _pricingMultiplier {
    switch (_pricingTier) {
      case 1:
        return 0.90; // سعر المقاول: تخفيض 10%
      case 2:
        return 0.82; // سعر المشروع: تخفيض 18%
      default:
        return 1.0; // سعر الورشة العادي
    }
  }

  DevisData get _effectiveDevisData {
    if (_pricingTier == 0) return _currentDevisData;
    final mult = _pricingMultiplier;
    final adjustedItems = _currentDevisData.items.map((it) {
      return DevisLineItem(
        imagePath: it.imagePath,
        imageBase64: it.imageBase64,
        title: it.title,
        details: it.details,
        unitPrice: (it.unitPrice * mult).roundToDouble(),
        quantity: it.quantity,
        isReplaced: it.isReplaced,
        replacementReason: it.replacementReason,
        width: it.width,
        height: it.height,
        color: it.color,
        detailId: it.detailId,
      );
    }).toList();

    final totalBrut = adjustedItems.fold<double>(
      0.0,
      (acc, item) =>
          acc + (item.isReplaced ? 0.0 : item.unitPrice * item.quantity),
    );
    final totalBeforeTax = totalBrut - _currentDevisData.remise;
    final tvaAmount = (totalBeforeTax * _currentDevisData.tvaPercent) / 100;
    final totalTTC = totalBeforeTax + tvaAmount;

    final String effectiveInvoiceNote = _currentDevisData.invoiceNote
        .replaceAll(DevisBuilder.pricingNotePattern, '')
        .trim();

    return DevisData(
      orderId: _currentDevisData.orderId,
      orderDate: _currentDevisData.orderDate,
      validUntil: _currentDevisData.validUntil,
      workshop: _currentDevisData.workshop,
      clientName: _currentDevisData.clientName,
      clientPhone: _currentDevisData.clientPhone,
      items: adjustedItems,
      totalBrut: totalBrut,
      remise: _currentDevisData.remise,
      totalBeforeTax: totalBeforeTax,
      totalHT: totalBeforeTax,
      tvaPercent: _currentDevisData.tvaPercent,
      tvaAmount: tvaAmount,
      totalTTC: totalTTC,
      amountPaid: _currentDevisData.amountPaid,
      amountInWords: _currentDevisData.amountInWords,
      invoiceNote: effectiveInvoiceNote,
      isPartial: _currentDevisData.isPartial,
      hidePrices: _currentDevisData.hidePrices,
      isProForma: _currentDevisData.isProForma,
      documentTitleKey: _currentDevisData.documentTitleKey,
      clientNif: _currentDevisData.clientNif,
      clientNis: _currentDevisData.clientNis,
      clientRc: _currentDevisData.clientRc,
      clientAi: _currentDevisData.clientAi,
      chequeNumber: _currentDevisData.chequeNumber,
      clientNumber: _currentDevisData.clientNumber,
      clientId: _currentDevisData.clientId,
      sequenceNumber: _currentDevisData.sequenceNumber,
      priorConfirmedWindowsCount: _currentDevisData.priorConfirmedWindowsCount,
      orderStatus: _currentDevisData.orderStatus,
      isConfirmed: _currentDevisData.isConfirmed,
      isDiscountApplicable: _currentDevisData.isDiscountApplicable,
      rawOrder: _currentDevisData.rawOrder,
      rawItems: _currentDevisData.rawItems,
    );
  }

  // The visual Devis is already available from DevisData. PDF bytes are
  // prepared in the background and must not block opening the preview.
  bool _isLoading = false;
  bool _isPdfGenerating = false;
  bool _isActionInProgress = false;
  String? _pdfError;
  Uint8List? _pdfBytes;
  Future<Uint8List?>? _pdfBuildFuture;
  int? _pdfBuildRevision;
  int _pdfRevision = 0;

  void _invalidatePdfCache() {
    _pdfRevision++;
    _pdfBytes = null;
    _pdfError = null;
  }

  String t(String key) {
    try {
      return Localization.translate(key, _invoiceLanguage);
    } catch (_) {
      return key;
    }
  }

  AppLanguage get lang => _invoiceLanguage;

  DevisData get data => _effectiveDevisData;

  bool get _isOfficial =>
      data.isProForma ||
      data.documentTitleKey == 'FACTURE_VENTE' ||
      data.documentTitleKey == 'BON_ROUTE';

  bool get _isBonLivraison {
    final key = data.documentTitleKey ?? '';
    return key == 'doc_bon_livraison' ||
        key == 'doc_bon_livraison_sans_prix' ||
        key == 'doc_bon_livraison_partiel' ||
        key == 'doc_bon_livraison_partiel_sans_prix' ||
        key == 'BON_CHARGE';
  }

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
    _activeDeliveryId = widget.deliveryId;
    _isLoaded = widget.initialIsLoaded;
    _invoiceLanguage = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    // Generate the PDF in the background after the screen renders. The visual preview must remain
    // instant and usable while PDF bytes are being prepared; widget.data is already built.
    unawaited(_checkExistingDelivery());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _initPdfGeneration();
      }
    });
  }

  Future<void> _checkExistingDelivery() async {
    if (!_isBonLivraison || data.orderId <= 0) return;
    try {
      final deliveries = await SqlDatabase().readCommandeDeliveries(
        data.orderId,
      );
      if (deliveries.isNotEmpty) {
        final loadedRecord = _activeDeliveryId != null
            ? deliveries.firstWhere(
                (d) => (d['id'] as num?)?.toInt() == _activeDeliveryId,
                orElse: () => deliveries.first,
              )
            : deliveries.firstWhere(
                (d) => (d['is_loaded'] as num?)?.toInt() == 1,
                orElse: () => deliveries.first,
              );
        if (mounted) {
          setState(() {
            _activeDeliveryId = (loadedRecord['id'] as num?)?.toInt();
            _isLoaded = (loadedRecord['is_loaded'] as num?)?.toInt() == 1;
            _activeDeliveryDate = loadedRecord['delivery_date']?.toString();
          });
        }
      }
    } catch (_) {}
  }

  Future<void> _validateDelivery(BuildContext context) async {
    final isFr = _invoiceLanguage == AppLanguage.french;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Row(
          children: [
            const Icon(Icons.check_circle_outline, color: Colors.green),
            const SizedBox(width: 8),
            Text(isFr ? 'Valider la livraison' : 'تأكيد التسليم'),
          ],
        ),
        content: Text(
          isFr
              ? 'Confirmez-vous que le client a bien reçu cette marchandise ? Le bon de livraison sera validé et enregistré dans le dossier du client.'
              : 'هل تؤكد استلام الزبون لهذه السلع فعلياً؟ سيتم تأكيد وصل التسليم وتسجيله في سجل تفاصيل الزبون وتحديث حالة الطلبية.',
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(isFr ? 'Annuler' : 'إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.green,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            icon: const Icon(Icons.check, size: 18),
            label: Text(
              isFr ? 'Confirmer (Validé)' : 'تأكيد (Validé)',
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                fontFamily: 'Cairo',
              ),
            ),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    try {
      final db = SqlDatabase();
      int orderId = data.orderId;
      int clientId = data.clientId;
      if (clientId <= 0 && orderId > 0) {
        final order = await db.readCommandeWithClientById(orderId);
        if (order != null && order['client_id'] != null) {
          clientId = (order['client_id'] as num).toInt();
        }
      }

      final now = DateTime.now();
      final dateStr = DateFormat('yyyy-MM-dd HH:mm').format(now);

      List<Map<String, dynamic>> itemsList = [];
      if (data.rawItems != null && data.rawItems!.isNotEmpty) {
        itemsList = data.rawItems!;
      } else {
        itemsList = data.items
            .map(
              (it) => {
                'id': it.detailId,
                'name': it.title,
                'quantity': it.quantity,
                'price': it.unitPrice,
                'width': it.width,
                'height': it.height,
                'description': it.details.join('\n'),
                'drawing_image_path': it.imagePath,
              },
            )
            .toList();
      }

      if (_activeDeliveryId != null) {
        await db.updateCommandeDeliveryIsLoaded(_activeDeliveryId!, 1);
      } else {
        int? existingDelId;
        if (orderId > 0) {
          final existingDeliveries = await db.readCommandeDeliveries(orderId);
          if (existingDeliveries.isNotEmpty) {
            existingDelId = (existingDeliveries.first['id'] as num?)?.toInt();
          }
        }
        if (existingDelId != null && existingDelId > 0) {
          await db.updateCommandeDeliveryIsLoaded(existingDelId, 1);
          _activeDeliveryId = existingDelId;
        } else {
          final newDeliveryId = await db.insertCommandeDelivery(
            orderId,
            clientId,
            dateStr,
            jsonEncode(itemsList),
            data.totalTTC,
            isLoaded: 1,
          );
          _activeDeliveryId = newDeliveryId;
          _activeDeliveryDate = dateStr;
        }
      }

      // 🚚 تحديث حالة الطلبية مباشرة إلى توزيع جزئي أو توزيع كلي
      final bool isFull = !data.isPartial;
      final targetStatus = isFull
          ? 'Full Distribution'
          : 'Partial Distribution';
      if (orderId > 0) {
        await db.updateCommandeStatus(
          orderId,
          targetStatus,
          skipAllocationSync: true,
        );
        await db.markItemsAllocationsTransferred(
          orderId,
          itemsList,
          isFullOrder: isFull,
        );
        await db.syncOrderAndAllocationsStatus(orderId);
      }
      CloudSyncService().notifyChange();

      setState(() {
        _isLoaded = true;
        _activeDeliveryDate ??= dateStr;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isFr
                  ? 'Livraison validée avec succès et enregistrée dans le dossier client !'
                  : 'تم تأكيد التسليم بنجاح وتسجيل وصل التسليم في ملف الزبون!',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'خطأ أثناء تأكيد التسليم: $e',
              style: const TextStyle(fontFamily: 'Cairo'),
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _debounceTimer?.cancel();
    super.dispose();
  }

  Future<void> _initPdfGeneration() async {
    if (mounted) {
      setState(() {
        _isPdfGenerating = true;
        _pdfError = null;
      });
    }
    try {
      final bytes = await _obtainLatestPdfBytes(showErrors: false);
      if (mounted) {
        setState(() {
          if (bytes == null) {
            _pdfError = _pdfGenerationErrorMessage;
          }
        });
      }
    } catch (e) {
      debugPrint('PDF generation error: $e');
      if (mounted) {
        setState(() {
          _pdfError = _pdfGenerationErrorMessage;
        });
      }
    } finally {
      if (mounted) setState(() => _isPdfGenerating = false);
    }
  }

  String get _pdfGenerationErrorMessage =>
      _invoiceLanguage == AppLanguage.french
      ? 'La génération du document a échoué. Réessayez.'
      : 'تعذر توليد الوثيقة. اضغط لإعادة المحاولة.';

  Future<Uint8List?> _buildPdfBytes({
    required DevisData pdfData,
    required AppLanguage language,
    required int imageMode,
    bool showErrors = true,
  }) async {
    try {
      return await PdfInvoiceApi.buildPdfBytes(
        pdfData,
        overrideLang: language,
        imageMode: imageMode,
      );
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

  Future<Uint8List?> _obtainLatestPdfBytes({bool showErrors = true}) async {
    while (mounted) {
      final cached = _pdfBytes;
      if (cached != null) return cached;

      final requestedRevision = _pdfRevision;
      var future = _pdfBuildFuture;

      if (future == null) {
        final pdfData = _effectiveDevisData;
        final language = _invoiceLanguage;
        final imageMode = _imageMode;
        future = _buildPdfBytes(
          pdfData: pdfData,
          language: language,
          imageMode: imageMode,
          showErrors: showErrors,
        );
        _pdfBuildFuture = future;
        _pdfBuildRevision = requestedRevision;
      }

      final runningRevision = _pdfBuildRevision;
      final bytes = await future;

      if (identical(_pdfBuildFuture, future)) {
        _pdfBuildFuture = null;
        _pdfBuildRevision = null;
      }
      if (!mounted) return null;

      // The user changed language, image placement, pricing, or cheque data
      // while this build was running. Discard it and build the latest state.
      if (runningRevision != _pdfRevision) continue;

      if (bytes != null) _pdfBytes = bytes;
      return bytes;
    }
    return null;
  }

  Future<Uint8List?> _ensurePdfBytes() async {
    if (_pdfBytes != null) return _pdfBytes;

    if (mounted) {
      setState(() {
        _isPdfGenerating = true;
        _pdfError = null;
      });
    }
    try {
      final bytes = await _obtainLatestPdfBytes();
      if (mounted && bytes != null) {
        setState(() => _pdfBytes = bytes);
      } else if (mounted) {
        setState(() => _pdfError = _pdfGenerationErrorMessage);
      }
      return bytes;
    } finally {
      if (mounted) setState(() => _isPdfGenerating = false);
    }
  }

  Future<void> _changeInvoiceLanguage(AppLanguage newLang) async {
    if (_isLoading) return;
    setState(() {
      _isLoading = true;
      _invoiceLanguage = newLang;
      _invalidatePdfCache();
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

      if (mounted) {
        setState(() {
          _currentDevisData = rebuiltData;
          _invalidatePdfCache();
        });
      }
      await _initPdfGeneration();
      if (mounted) setState(() => _isLoading = false);
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
      _invalidatePdfCache();
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

      if (mounted) {
        setState(() {
          _currentDevisData = rebuiltData;
          _invalidatePdfCache();
        });
      }
      await _initPdfGeneration();
      if (mounted) setState(() => _isLoading = false);
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            physics: const BouncingScrollPhysics(),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
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
                const SizedBox(width: 14),
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
          ),
          if (!_isOfficial) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.dashboard_customize_outlined,
                        color: _blue,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _invoiceLanguage == AppLanguage.french
                            ? 'Disposition de l\'image :'
                            : 'مكان وشكل الصورة :',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── وضع A: صورة جانبية ──
                        _modeButton(0, 'A (Latérale)', 'A (جانبية)'),
                        // ── وضع B: صورة تحت التفاصيل ──
                        _modeButton(1, 'B (Sous prix)', 'B (تحت الأسعار)'),
                        // ── وضع C: صورة تحت كامل الصف ──
                        _modeButton(2, 'C (Pleine)', 'C (تحت الصف)'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (!data.hidePrices) ...[
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.price_change_outlined,
                        color: Colors.teal,
                        size: 20,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _invoiceLanguage == AppLanguage.french
                            ? 'Niveau de prix :'
                            : 'مستوى وفئة السعر :',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                          fontFamily: 'Cairo',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(width: 14),
                  Container(
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        // ── 0: سعر الورشة العادي ──
                        _pricingTierButton(
                          0,
                          'Atelier (100%)',
                          'سعر الورشة',
                          _blue,
                        ),
                        // ── 1: سعر المقاول ──
                        _pricingTierButton(
                          1,
                          'Artisan / Entreprise (-10%)',
                          'سعر المقاول (-10%)',
                          Colors.orange.shade800,
                        ),
                        // ── 2: سعر المشروع ──
                        _pricingTierButton(
                          2,
                          'Projet / Promoteur (-18%)',
                          'سعر المشروع (-18%)',
                          Colors.teal.shade700,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
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
        if (_activeDeliveryId != null || _isBonLivraison) ...[
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
                              ? 'Statut: Livraison validée ✓'
                              : 'الحالة: تم تأكيد التسليم بنجاح ✓')
                        : (isFr
                              ? 'Statut: En attente de livraison'
                              : 'الحالة: معلق - لم يتم تأكيد التسليم بعد'),
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
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                    ),
                    onPressed: () => _validateDelivery(context),
                    icon: const Icon(
                      Icons.check,
                      size: 16,
                      color: Colors.white,
                    ),
                    label: Text(
                      isFr ? 'Valider (Validé)' : 'تأكيد التسليم (Validé)',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
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
        if (data.invoiceNote.trim().isNotEmpty) ...[
          const SizedBox(height: 12),
          _buildDocumentNote(data.invoiceNote.trim()),
        ],
        _buildFooter(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    //final isBonDeCharge = data.documentTitleKey == 'BON_CHARGE';

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
              if (_isPdfGenerating || _pdfError != null)
                Material(
                  color: _pdfError == null
                      ? Colors.blue.shade50
                      : Colors.red.shade50,
                  child: InkWell(
                    onTap: _pdfError == null
                        ? null
                        : () {
                            setState(_invalidatePdfCache);
                            unawaited(_initPdfGeneration());
                          },
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      child: Row(
                        children: [
                          if (_isPdfGenerating)
                            const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          else
                            const Icon(
                              Icons.refresh,
                              size: 18,
                              color: Colors.red,
                            ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _isPdfGenerating
                                  ? (_invoiceLanguage == AppLanguage.french
                                        ? 'Préparation du PDF en arrière-plan…'
                                        : 'يتم تجهيز ملف PDF في الخلفية…')
                                  : _pdfError!,
                              style: TextStyle(
                                fontSize: 12,
                                fontFamily: 'Cairo',
                                color: _pdfError == null
                                    ? Colors.blue.shade900
                                    : Colors.red.shade900,
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
                  padding: const EdgeInsets.all(12),
                  child: Container(
                    decoration: BoxDecoration(
                      // A document is paper: keep it white in dark mode too.
                      // Most invoice text intentionally uses print-safe black.
                      color: Colors.white,
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
                          if (_isBonLivraison) ...[
                            _buildBonLivraisonBanner(context),
                          ],
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
                          if (data.invoiceNote.trim().isNotEmpty) ...[
                            const SizedBox(height: 12),
                            _buildDocumentNote(data.invoiceNote.trim()),
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

    final seq = data.orderDisplayNumber;
    final seqNum = seq.toString().padLeft(3, '0');
    return '$prefix$year2$seqNum';
  }

  String get _documentOrderReferenceText {
    final num = data.orderDisplayNumber;
    if (_invoiceLanguage == AppLanguage.french) {
      return 'Pour la commande N° $num';
    } else if (_invoiceLanguage == AppLanguage.english) {
      return 'For order #$num';
    } else {
      return 'للطلبية رقم $num';
    }
  }

  String get _orderMetaLabel {
    if (_invoiceLanguage == AppLanguage.french) {
      return 'Commande N°:';
    } else if (_invoiceLanguage == AppLanguage.english) {
      return 'Order N°:';
    } else {
      return 'الطلبية رقم:';
    }
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
                  const SizedBox(height: 2),
                  Text(
                    _documentOrderReferenceText,
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.blueGrey.shade700,
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
                _metaLine(_orderMetaLabel, '#${data.orderDisplayNumber}'),
                _metaLine('Date:', data.orderDate),
                if (_isBonLivraison &&
                    (_activeDeliveryDate != null || _isLoaded))
                  _metaLine(
                    _invoiceLanguage == AppLanguage.french
                        ? 'Date sortie / livraison:'
                        : 'تاريخ الخروج / التسليم:',
                    _activeDeliveryDate ?? data.orderDate,
                  ),
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
            if (_isOfficial || _isBonLivraison) ...[
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

  Widget _buildBonLivraisonBanner(BuildContext context) {
    final isFr = _invoiceLanguage == AppLanguage.french;
    final remaining = (data.totalTTC - data.amountPaid);
    final isSoldOut = remaining <= 0.01;
    final exitDate = _activeDeliveryDate ?? data.orderDate;

    return Container(
      margin: const EdgeInsets.only(top: 14, bottom: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _isLoaded ? const Color(0xFFE8F5E9) : const Color(0xFFFFF8E1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: _isLoaded ? const Color(0xFF81C784) : const Color(0xFFFFD54F),
          width: 1.2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isLoaded ? Icons.verified : Icons.info_outline,
                color: _isLoaded
                    ? Colors.green.shade800
                    : Colors.amber.shade900,
                size: 20,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  isFr
                      ? 'ATTESTATION DE SORTIE & LIVRAISON DE MARCHANDISE'
                      : 'وصل وإثبات خروج وتسليم السلع من الورشة',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: _isLoaded
                        ? Colors.green.shade900
                        : Colors.amber.shade900,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 3,
                ),
                decoration: BoxDecoration(
                  color: _isLoaded
                      ? Colors.green.shade700
                      : Colors.amber.shade700,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _isLoaded
                      ? (isFr ? 'VALIDÉ / SORTI' : 'مؤكد / خرجت من الورشة')
                      : (isFr ? 'EN ATTENTE' : 'في انتظار الخروج والتأكيد'),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    fontFamily: 'Cairo',
                  ),
                ),
              ),
            ],
          ),
          const Divider(height: 16, thickness: 0.8),
          Wrap(
            spacing: 16,
            runSpacing: 8,
            children: [
              _bannerInfoItem(
                icon: Icons.calendar_today,
                label: isFr ? 'Date de commande :' : 'تقدم بالطلب بتاريخ :',
                value: data.orderDate,
              ),
              _bannerInfoItem(
                icon: Icons.outbox,
                label: isFr
                    ? 'Date de sortie / livraison :'
                    : 'تاريخ الخروج والتسليم :',
                value: exitDate,
                isHighlight: true,
              ),
              _bannerInfoItem(
                icon: Icons.payments_outlined,
                label: isFr ? 'Avance payée :' : 'دفع مقدماً :',
                value: data.amountPaid > 0
                    ? '${data.amountPaid.toStringAsFixed(2)} DZD'
                    : (isFr ? 'Aucune avance' : 'بدون تسبيق'),
              ),
              _bannerInfoItem(
                icon: isSoldOut ? Icons.check_circle : Icons.pending_actions,
                label: isFr ? 'Règlement / Solde :' : 'حالة الحساب الباقي :',
                value: isSoldOut
                    ? (isFr
                          ? 'Compte soldé (Payé intégralement)'
                          : 'أكمل الحساب بالكامل (Soldé)')
                    : (isFr
                          ? 'Reste: ${remaining.toStringAsFixed(2)} DZD'
                          : 'المتبقي: ${remaining.toStringAsFixed(2)} دج'),
                isSuccess: isSoldOut,
              ),
              _bannerInfoItem(
                icon: Icons.inventory_2_outlined,
                label: isFr ? 'Type de livraison :' : 'نوع التسليم :',
                value: data.isPartial
                    ? (isFr ? 'Livraison partielle' : 'تسليم جزئي (توزيع جزئي)')
                    : (isFr ? 'Livraison totale' : 'تسليم كلي (توزيع كلي)'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _bannerInfoItem({
    required IconData icon,
    required String label,
    required String value,
    bool isHighlight = false,
    bool isSuccess = false,
  }) {
    Color valColor = Colors.black87;
    if (isHighlight) valColor = const Color(0xFF1565C0);
    if (isSuccess) valColor = Colors.green.shade800;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 15, color: Colors.blueGrey.shade600),
        const SizedBox(width: 4),
        Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            color: Colors.blueGrey.shade800,
            fontWeight: FontWeight.w600,
            fontFamily: 'Cairo',
          ),
        ),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.bold,
            color: valColor,
            fontFamily: 'Cairo',
          ),
        ),
      ],
    );
  }

  Widget _buildTableHeader() {
    final hidePrices = data.hidePrices;
    final bool showLeftImage = !_isOfficial && _imageMode == 0;

    return Container(
      color: _headerBlue,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      child: Row(
        children: [
          if (showLeftImage)
            SizedBox(width: 88, child: Text(t('Image'), style: _headerStyle)),
          Expanded(
            flex: hidePrices ? 8 : (showLeftImage ? 4 : 5),
            child: Text(t('Désignation'), style: _headerStyle),
          ),
          if (!hidePrices)
            Expanded(
              flex: 2,
              child: Text(
                _isOfficial ? t('P.U. H.T.') : t('Prix Unit.'),
                style: _headerStyle,
                textAlign: TextAlign.end,
              ),
            ),
          SizedBox(
            width: 38,
            child: Text(
              t('Qté'),
              style: _headerStyle,
              textAlign: TextAlign.end,
            ),
          ),
          if (!hidePrices)
            Expanded(
              flex: 2,
              child: Text(
                _isOfficial ? t('TOTAL H.T.') : t('Total'),
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

  /// زر تبديل وضع الصورة (A=0 / B=1 / C=2)
  Widget _modeButton(int mode, String labelFr, String labelAr) {
    final bool active = _imageMode == mode;
    final String label = _invoiceLanguage == AppLanguage.french
        ? labelFr
        : labelAr;
    return GestureDetector(
      onTap: () {
        if (!active && !_isLoading) {
          setState(() {
            _imageMode = mode;
            _invalidatePdfCache();
          });
          unawaited(_initPdfGeneration());
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _blue : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  /// زر تبديل مستوى التسعير (0=ورشة / 1=مقاول / 2=مشروع)
  Widget _pricingTierButton(
    int tier,
    String labelFr,
    String labelAr,
    Color activeColor,
  ) {
    final bool active = _pricingTier == tier;
    final String label = _invoiceLanguage == AppLanguage.french
        ? labelFr
        : labelAr;
    return GestureDetector(
      onTap: () {
        if (!active && !_isLoading) {
          setState(() {
            _pricingTier = tier;
            _invalidatePdfCache();
          });
          unawaited(_initPdfGeneration());
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: active ? activeColor : Colors.transparent,
          borderRadius: BorderRadius.circular(18),
        ),
        child: Text(
          label,
          style: TextStyle(
            color: active ? Colors.white : Colors.black87,
            fontWeight: FontWeight.bold,
            fontSize: 12,
            fontFamily: 'Cairo',
          ),
        ),
      ),
    );
  }

  Widget _buildItemRow(int index, DevisLineItem item) {
    final bg = index.isEven ? Colors.white : const Color(0xFFF8FAFC);
    final textColor = item.isReplaced ? Colors.grey.shade500 : Colors.black87;
    final detailColor = item.isReplaced
        ? Colors.grey.shade400
        : Colors.grey.shade800;
    final priceColor = item.isReplaced ? Colors.grey.shade500 : _blue;
    final hidePrices = data.hidePrices;
    final bool showLeftImage = !_isOfficial && _imageMode == 0;
    final List<String> displayDetails = _isOfficial
        ? [
            if (_invoiceLanguage == AppLanguage.french)
              'Largeur: ${item.width} mm | Hauteur: ${item.height} mm'
            else if (_invoiceLanguage == AppLanguage.english)
              'Width: ${item.width} mm | Height: ${item.height} mm'
            else
              'العرض: ${item.width} مم | الارتفاع: ${item.height} مم',
          ]
        : item.details;

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
                if (showLeftImage) ...[
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
                  flex: hidePrices ? 8 : (showLeftImage ? 4 : 5),
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
                      _detailsBlock(
                        displayDetails,
                        detailColor,
                        twoColumns: hidePrices,
                      ),
                      // وضع B: صورة تحت التفاصيل داخل عمود التسمية
                      if (_imageMode == 1 && !_isOfficial) ...[
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          height: 180,
                          child: Opacity(
                            opacity: item.isReplaced ? 0.6 : 1.0,
                            child: _buildItemImage(item),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                ...[
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
              ],
            ),
          ),
          // وضع C: صورة تحت كامل صف السعر/الكمية
          if (_imageMode == 2 && !_isOfficial) ...[
            const SizedBox(height: 8),
            LayoutBuilder(
              builder: (context, constraints) {
                final double ratio = (item.width > 0 && item.height > 0)
                    ? item.width / item.height
                    : 4 / 3;
                final double imgW = constraints.maxWidth;
                final double imgH = (imgW / ratio).clamp(0.0, 280.0).toDouble();
                return Center(
                  child: Opacity(
                    opacity: item.isReplaced ? 0.6 : 1.0,
                    child: Container(
                      width: imgW,
                      height: imgH,
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: bg,
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: _buildItemImage(item),
                    ),
                  ),
                );
              },
            ),
            const SizedBox(height: 4),
          ],
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

  Widget _detailsBlock(
    List<String> details,
    Color color, {
    required bool twoColumns,
  }) {
    final clean = details.where((item) => item.trim().isNotEmpty).toList();
    if (clean.isEmpty) return const SizedBox.shrink();

    Widget column(List<String> values) => Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final value in values)
          _detailRichText(value, style: TextStyle(fontSize: 11, color: color)),
      ],
    );

    if (!twoColumns || clean.length < 2) return column(clean);

    final split = (clean.length + 1) ~/ 2;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(child: column(clean.sublist(0, split))),
        const SizedBox(width: 8),
        Expanded(child: column(clean.sublist(split))),
      ],
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

    // A drawing path belongs to the device that created the order.  On a
    // different device the portable Base64 copy may be available even when
    // that path is invalid.
    if (item.imageBase64 != null && item.imageBase64!.trim().isNotEmpty) {
      try {
        final raw = item.imageBase64!.trim();
        final separator = raw.indexOf(',');
        final encoded = raw.startsWith('data:image') && separator >= 0
            ? raw.substring(separator + 1)
            : raw;
        final bytes = base64Decode(encoded);
        if (bytes.isNotEmpty) {
          return Container(
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              border: Border.all(color: Colors.grey.shade300),
              borderRadius: BorderRadius.circular(4),
            ),
            padding: const EdgeInsets.all(4),
            child: Image.memory(bytes, fit: BoxFit.contain),
          );
        }
      } catch (_) {
        // Fall through to the local-path and legacy asset fallbacks.
      }
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

    // Keep the official asset only as a compatibility fallback for old
    // Caisson Tunnel rows that have no readable saved drawing.
    if (item.title.contains('Caisson Tunnel') ||
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Arrêtée la présente facture à la somme de: ${data.amountInWords}.',
          style: const TextStyle(fontSize: 12, color: Colors.black87),
        ),
      ],
    );
  }

  Widget _buildTotals() {
    final bool isOfficial = _isOfficial;
    final documentKey = (data.documentTitleKey ?? '').toUpperCase();
    final bool isDevis =
        !isOfficial &&
        (documentKey.isEmpty ||
            documentKey == 'DOC_DEVIS' ||
            documentKey == 'DEVIS' ||
            documentKey == 'DEVIS_PARTIAL');
    final totalBrutLabel = isOfficial ? 'TOTAL HT' : t('Total Brut');
    final remiseLabel = isOfficial ? 'REMISE' : t('Remise');
    final netHtLabel = isOfficial ? 'NET HT' : t('Total après remise');
    final tvaLabel = isOfficial
        ? 'TVA'
        : 'TVA (${data.tvaPercent.toStringAsFixed(0)}%)';
    final totalTtcLabel = isOfficial ? 'NET A PAYER' : t('TOTAL TTC');
    final amountRemaining = (data.totalTTC - data.amountPaid)
        .clamp(0.0, double.infinity)
        .toDouble();

    final bool showRemise =
        isDevis || (data.isDiscountApplicable && data.remise > 0);
    final bool showTva =
        isDevis || isOfficial || data.tvaPercent > 0 || data.tvaAmount > 0;

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _totalRow(totalBrutLabel, data.totalBrut),
            if (showRemise) ...[
              _totalRow(remiseLabel, data.remise),
              _totalRow(netHtLabel, data.totalBeforeTax),
            ],
            if (showTva) _totalRow(tvaLabel, data.tvaAmount),
            _totalRow(totalTtcLabel, data.totalTTC, highlight: true),
            if (data.showsPayments) ...[
              if (isDevis)
                _totalRow(t('Montant payé'), data.amountPaid)
              else if (data.amountPaid > 0)
                _totalRow(
                  t('Montant payé'),
                  data.amountPaid,
                  color: Colors.green,
                ),
              if (!isDevis && (data.amountPaid > 0 || isOfficial))
                _totalRow(t('Remaining:'), amountRemaining, color: Colors.red),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDocumentNote(String note) {
    final cleanNote = note.trim();
    if (cleanNote.isEmpty) return const SizedBox.shrink();

    final isAr = _invoiceLanguage == AppLanguage.arabic;
    final isFr = _invoiceLanguage == AppLanguage.french;
    final label = isFr ? 'Remarque:' : (isAr ? 'ملاحظة:' : 'Note:');
    final lines = cleanNote
        .split('\n')
        .where((l) => l.trim().isNotEmpty)
        .toList();

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.only(top: 8),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: Color(0xFFE0E0E0), width: 0.8)),
      ),
      child: Column(
        crossAxisAlignment: isAr
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: isAr
                ? MainAxisAlignment.end
                : MainAxisAlignment.start,
            children: [
              Text(
                label,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Colors.black87,
                  fontFamily: 'Cairo',
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          ...lines.map(
            (line) => Padding(
              padding: const EdgeInsets.only(bottom: 2),
              child: Text(
                line,
                textAlign: isAr ? TextAlign.right : TextAlign.left,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: Colors.black87,
                  fontFamily: 'Cairo',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter() {
    final isOfficial = _isOfficial;
    final parts = <String>[];
    if (isOfficial) {
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
      if (data.workshop.phone.isNotEmpty) {
        parts.add('Tél: ${data.workshop.phone}');
      }
    }

    final footerText = parts.join(' | ');
    if (footerText.isEmpty) return const SizedBox.shrink();

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

  Widget _totalRow(
    String label,
    double value, {
    bool highlight = false,
    Color? color,
  }) {
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
          Text(label, style: TextStyle(fontSize: 12, color: color)),
          Text(
            '${_formatMoney(value)} D.A',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomActions(BuildContext context) {
    final bool ready = !_isActionInProgress;
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
            if (_isBonLivraison) ...[
              Expanded(
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isLoaded
                        ? Colors.grey.shade600
                        : Colors.green.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  onPressed: _isLoaded
                      ? null
                      : () => _validateDelivery(context),
                  icon: Icon(
                    _isLoaded ? Icons.check_circle : Icons.verified_outlined,
                    size: 16,
                  ),
                  label: Text(
                    _isLoaded
                        ? (_invoiceLanguage == AppLanguage.french
                              ? 'Livré ✓'
                              : 'مُسلَّم ✓')
                        : 'Validé',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      fontFamily: 'Cairo',
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
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
                icon: Icon(
                  _isActionInProgress ? Icons.hourglass_top : Icons.save,
                  size: 16,
                ),
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

    if (mounted) setState(() => _isActionInProgress = true);
    try {
      final bytes = _pdfBytes ?? await _ensurePdfBytes();
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _pdfError ?? _pdfGenerationErrorMessage,
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
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
        // Android/iOS: write to temp then use system dialog, with Printing.sharePdf as safe fallback
        try {
          final tempDir = await getTemporaryDirectory();
          final tempFile = File('${tempDir.path}/$filename');
          await tempFile.writeAsBytes(bytes);
          final params = SaveFileDialogParams(sourceFilePath: tempFile.path);
          finalPath = await FlutterFileDialog.saveFile(params: params);
        } catch (_) {
          final shared = await Printing.sharePdf(
            bytes: bytes,
            filename: filename,
          );
          if (shared) {
            finalPath = filename;
          }
        }
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
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _printPdf(BuildContext context) async {
    if (mounted) setState(() => _isActionInProgress = true);
    try {
      final bytes = _pdfBytes ?? await _ensurePdfBytes();
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _pdfError ?? _pdfGenerationErrorMessage,
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
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
      if (mounted) setState(() => _isActionInProgress = false);
    }
  }

  Future<void> _sharePdf(BuildContext context) async {
    if (mounted) setState(() => _isActionInProgress = true);
    try {
      final bytes = _pdfBytes ?? await _ensurePdfBytes();
      if (bytes == null) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                _pdfError ?? _pdfGenerationErrorMessage,
                style: const TextStyle(fontFamily: 'Cairo'),
              ),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final filename = sharedPdfFilename(
        documentType: 'Devis',
        orderNumber: data.orderId,
        clientName: data.clientName,
      );
      // A real temporary file preserves the attachment name across Android,
      // iOS and Windows. The ASCII-safe client slug avoids URL-encoded Arabic
      // names appearing as percent sequences in receiving applications.
      final tempDirectory = await getTemporaryDirectory();
      final separator = Platform.isWindows ? '\\' : '/';
      final file = File('${tempDirectory.path}$separator$filename');
      await file.writeAsBytes(bytes, flush: true);
      final shareTitle = t('مشاركة');
      await SharePlus.instance.share(
        ShareParams(
          files: [XFile(file.path, mimeType: 'application/pdf')],
          fileNameOverrides: [filename],
          title: shareTitle,
          subject: shareTitle,
          text: shareTitle,
        ),
      );
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
      if (mounted) setState(() => _isActionInProgress = false);
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
