import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:provider/provider.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/arabic_reshaper/arabic_reshaper.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../Screen/order_allocation_screen.dart';

class OrderMeasurementsConfirmScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;

  const OrderMeasurementsConfirmScreen({
    super.key,
    required this.orderData,
    required this.db,
  });

  @override
  State<OrderMeasurementsConfirmScreen> createState() =>
      _OrderMeasurementsConfirmScreenState();
}

class _OrderMeasurementsConfirmScreenState
    extends State<OrderMeasurementsConfirmScreen> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _detailsList = [];

  // Controllers maps: detailId -> list of instance editors
  final Map<int, List<InstanceEditor>> _editors = {};

  // Active edit index for each detailId
  final Map<int, int> _activeEditIndices = {};

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en;
    return ar;
  }

  @override
  void initState() {
    super.initState();
    _loadDetails();
  }

  Future<void> _loadDetails() async {
    try {
      setState(() {
        _isLoading = true;
      });

      final orderId = widget.orderData['id'] as int;
      final rawDetails = await widget.db.readCommandeDetails(orderId);

      _detailsList = List<Map<String, dynamic>>.from(rawDetails);

      _editors.clear();
      for (final detail in _detailsList) {
        final detailId = detail['id'] as int;
        final originalQty = detail['quantity'] as int;
        final originalW = detail['largeur'] as int;
        final originalH = detail['hauteur'] as int;
        final rawJson = detail['partitions_json'];
        
        // Extract default position from the WindowModel
        String defaultPos = '';
        if (rawJson != null) {
          try {
            Map<String, dynamic> map = {};
            if (rawJson is Map<String, dynamic>) {
              map = rawJson;
            } else {
              map = jsonDecode(rawJson.toString()) as Map<String, dynamic>;
            }
            defaultPos = map['position']?.toString() ?? '';
          } catch (_) {}
        }

        final instancesJson = detail['instances_json'];
        List<dynamic> parsedInstances = [];
        if (instancesJson != null && instancesJson.toString().isNotEmpty) {
          try {
            parsedInstances = jsonDecode(instancesJson.toString()) as List<dynamic>;
          } catch (_) {}
        }

        final List<InstanceEditor> editorsList = [];
        if (parsedInstances.isNotEmpty) {
          for (final inst in parsedInstances) {
            editorsList.add(InstanceEditor(
              widthCtrl: TextEditingController(text: inst['width']?.toString() ?? originalW.toString()),
              heightCtrl: TextEditingController(text: inst['height']?.toString() ?? originalH.toString()),
              qtyCtrl: TextEditingController(text: inst['qty']?.toString() ?? '1'),
              positionCtrl: TextEditingController(text: inst['position']?.toString() ?? defaultPos),
            ));
          }
        } else {
          // Default to 1 row representing all quantities
          editorsList.add(InstanceEditor(
            widthCtrl: TextEditingController(text: originalW.toString()),
            heightCtrl: TextEditingController(text: originalH.toString()),
            qtyCtrl: TextEditingController(text: originalQty.toString()),
            positionCtrl: TextEditingController(text: defaultPos),
          ));
        }

        _editors[detailId] = editorsList;
        int initSum = 0;
        for (var ed in editorsList) {
          initSum += int.tryParse(ed.qtyCtrl.text) ?? 0;
        }
        _activeEditIndices[detailId] = (initSum >= originalQty) ? -1 : (editorsList.length - 1);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء تحميل البيانات: $e')),
      );
    }
  }

  int _getSumQty(int detailId) {
    final list = _editors[detailId] ?? [];
    int sum = 0;
    for (final ed in list) {
      sum += int.tryParse(ed.qtyCtrl.text) ?? 0;
    }
    return sum;
  }

  Future<void> _saveInstances(int detailId, int totalQty) async {
    final list = _editors[detailId] ?? [];
    final sum = _getSumQty(detailId);
    if (sum != totalQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            'مجموع الكميات المفصلة ($sum) يجب أن يساوي الكمية الإجمالية ($totalQty)!',
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }

    final List<Map<String, dynamic>> data = [];
    for (final ed in list) {
      final w = int.tryParse(ed.widthCtrl.text) ?? 0;
      final h = int.tryParse(ed.heightCtrl.text) ?? 0;
      final q = int.tryParse(ed.qtyCtrl.text) ?? 0;
      final pos = ed.positionCtrl.text.trim();
      data.add({
        'width': w,
        'height': h,
        'qty': q,
        'position': pos,
      });
    }

    final jsonStr = jsonEncode(data);
    try {
      final myDb = await widget.db.db;
      if (myDb != null) {
        await myDb.update(
          'Commandes_details',
          {'instances_json': jsonStr},
          where: 'id = ?',
          whereArgs: [detailId],
        );
        await _loadDetails();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            backgroundColor: Colors.green,
            content: Text('تم حفظ تفاصيل قياسات هذه النافذة بنجاح!'),
          ),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('خطأ أثناء الحفظ: $e')),
      );
    }
  }

  // --- PDF Sticker Generation ---
  bool _hasArabic(String text) {
    return text.runes.any((r) => r >= 0x0600 && r <= 0x06FF);
  }

  String _ar(String text) {
    if (!_hasArabic(text)) return text;
    // 1. Reshape the entire text to get proper ligature forms (outputs FExx codepoints)
    final reshaped = ArabicReshaper.instance.reshape(text);
    // 2. Split BOTH original and reshaped by space
    final originalWords = text.split(' ');
    final reshapedWords = reshaped.split(' ');
    final result = <String>[];
    for (int i = 0; i < reshapedWords.length; i++) {
      final originalWord = i < originalWords.length ? originalWords[i] : '';
      final reshapedWord = reshapedWords[i];
      // 3. Use the ORIGINAL word to detect Arabic (before FExx conversion)
      //    then reverse the RESHAPED word's chars for LTR PDF rendering
      if (_hasArabic(originalWord)) {
        result.add(String.fromCharCodes(reshapedWord.runes.toList().reversed));
      } else {
        result.add(reshapedWord);
      }
    }
    // 4. Reverse word order (Arabic is RTL)
    return result.reversed.join(' ');
  }

  int _getSashCount(Map<String, dynamic> detail) {
    final gameName = (detail['game']?.toString() ?? '').toLowerCase();
    
    // Guess default sashes based on the game name
    int defaultSash = 1;
    if (gameName.contains('2') || 
        gameName.contains('double') || 
        gameName.contains('دوبل') || 
        gameName.contains('coulissant') || 
        gameName.contains('منزلق') ||
        gameName.contains('coul')) {
      defaultSash = 2;
    } else if (gameName.contains('3') || gameName.contains('triple')) {
      defaultSash = 3;
    } else if (gameName.contains('4')) {
      defaultSash = 4;
    }

    final rawJson = detail['partitions_json'];
    if (rawJson == null) return defaultSash;
    try {
      Map<String, dynamic> map = {};
      if (rawJson is Map<String, dynamic>) {
        map = rawJson;
      } else {
        map = jsonDecode(rawJson.toString()) as Map<String, dynamic>;
      }
      final model = WindowModel(db: widget.db);
      applyWindowModelFromMap(model, map);
      
      int sashes = 0;
      for (var z in model.zones) {
        if (z.content == ZoneContent.singleSash) {
          sashes += 1;
        } else if (z.content == ZoneContent.doubleSash) {
          sashes += 2;
        } else if (z.content == ZoneContent.slidingSash) {
          sashes += z.slidingSashesCount > 0 ? z.slidingSashesCount : 2;
        }
      }
      return sashes > 0 ? sashes : defaultSash;
    } catch (_) {
      return defaultSash;
    }
  }

  /// Returns glass dimensions by running the real BOM calculation —
  /// identical to what material_consumption_screen uses.
  /// Returns null if partitions_json is missing or has no glass items.
  Future<({int gw, int gh})?> _getGlassDimensionsFromBom(
      Map<String, dynamic> detail) async {
    final rawJson = detail['partitions_json'];
    if (rawJson == null) return null;
    try {
      Map<String, dynamic> map = {};
      if (rawJson is Map<String, dynamic>) {
        map = rawJson;
      } else {
        map = jsonDecode(rawJson.toString()) as Map<String, dynamic>;
      }

      // Load full model with catalog data (series, profiles from DB)
      final model = WindowModel(db: widget.db);
      await applyWindowModelAndLoadCatalog(model, map);

      // Run the same BOM computation used by material_consumption_screen
      final bomItems = ComponentCalculator.generateBom(model, {});

      // Find the first glass item with valid dimensions
      for (final item in bomItems) {
        if (item.category == 'glass' || item.category == 'panneau') {
          final w = item.length;       // glass width in mm
          final h = item.glassHeight;  // glass height in mm
          if (w != null && w > 0 && h != null && h > 0) {
            return (gw: w.round(), gh: h.round());
          }
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }


  Future<void> _printStickers({
    int? targetDetailId,
    int? targetInstanceIndex,
    int? targetWindowSubIndex,
  }) async {
    final clientName = widget.orderData['client_name']?.toString() ??
        widget.orderData['client_display']?.toString() ??
        '${widget.orderData['firstname'] ?? ''} ${widget.orderData['lastname'] ?? ''}'.trim();
    final cleanClientName = clientName.isNotEmpty ? clientName : 'Client';
    final projectName = widget.orderData['project_name']?.toString() ?? '';
    final orderId = widget.orderData['id'] as int;
    final priorConfirmedWindowsCount = await widget.db.getPriorConfirmedWindowsCount(orderId);

    // Top-left: project name if available, else client name
    final topLeftLabel = projectName.isNotEmpty ? projectName : cleanClientName;
    // Show client name at bottom only when project is shown on top
    final showClientAtBottom = projectName.isNotEmpty;

    // Load fonts
    final regularData = await rootBundle.load('assets/fonts/Amiri-Regular.ttf');
    final boldData = await rootBundle.load('assets/fonts/Amiri-Bold.ttf');
    final font = pw.Font.ttf(regularData);
    final fontBold = pw.Font.ttf(boldData);

    final pdf = pw.Document();

    // ── Step 1: compute total window count across ALL instances ──────────────
    int totalWindowCount = 0;
    for (final detail in _detailsList) {
      final instancesJson = detail['instances_json'];
      List<Map<String, dynamic>> tmpInstances = [];
      if (instancesJson != null && instancesJson.toString().isNotEmpty) {
        try {
          final decoded = jsonDecode(instancesJson.toString()) as List<dynamic>;
          tmpInstances = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
        } catch (_) {}
      }
      if (tmpInstances.isEmpty) {
        totalWindowCount += detail['quantity'] as int;
      } else {
        for (final inst in tmpInstances) {
          totalWindowCount += (inst['qty'] as int? ?? 0);
        }
      }
    }

    // ── Step 2: unified sticker builder ─────────────────────────────────────
    pw.Page buildStickerPage({
      required int windowNum,
      required String pieceLabel,
      required int w,
      required int h,
      required String pos,
      required String gameName,
      required String barData,
      String? glassDims,
      String siteName = '',
    }) {
      final cumTicketNum = priorConfirmedWindowsCount + windowNum;

      return pw.Page(
        pageFormat: PdfPageFormat(
          50 * PdfPageFormat.mm,
          30 * PdfPageFormat.mm,
          marginAll: 1 * PdfPageFormat.mm,
        ),
        theme: pw.ThemeData.withFont(base: font, bold: fontBold),
        build: (pw.Context ctx) {
          return pw.Container(
            padding: const pw.EdgeInsets.all(1),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(color: PdfColors.black, width: 0.5),
            ),
            child: pw.Column(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                // ── Row 1: top-left = project/client | top-right = N / Total ──
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text(
                      _ar(topLeftLabel),
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                    pw.Text(
                      '$windowNum / $totalWindowCount',
                      style: pw.TextStyle(
                        fontSize: 6,
                        fontWeight: pw.FontWeight.bold,
                      ),
                    ),
                  ],
                ),

                // ── Row 2: big number + piece type | info block ──
                pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                  crossAxisAlignment: pw.CrossAxisAlignment.center,
                  children: [
                    // Big sequential number + piece type
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.center,
                      children: [
                        pw.Text(
                          '$windowNum',
                          style: pw.TextStyle(
                            fontSize: 18,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        pw.Text(
                          '#$cumTicketNum',
                          style: pw.TextStyle(
                            fontSize: 7,
                            fontWeight: pw.FontWeight.bold,
                            color: PdfColors.blueGrey800,
                          ),
                        ),
                        pw.Text(
                          _ar(pieceLabel),
                          style: const pw.TextStyle(fontSize: 5),
                        ),
                      ],
                    ),
                    // Info block
                    pw.Column(
                      crossAxisAlignment: pw.CrossAxisAlignment.start,
                      children: [
                        // Frame dimensions + Position/Location (الموقع)
                        pw.Text(
                          '${w}×${h} mm' + (pos.isNotEmpty ? ' - ${_ar(pos)}' : ''),
                          style: pw.TextStyle(
                            fontSize: 7.5,
                            fontWeight: pw.FontWeight.bold,
                          ),
                        ),
                        // Glass dimensions (if available)
                        if (glassDims != null)
                          pw.Text(
                            'Verre: $glassDims',
                            style: pw.TextStyle(
                              fontSize: 6.5,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.blue900,
                            ),
                          ),
                        // System/Game name
                        pw.Text(
                          _ar(gameName),
                          style: const pw.TextStyle(fontSize: 6),
                        ),
                        // Order details + Client
                        pw.Text(
                          'CMD #$orderId' + (showClientAtBottom ? ' | ${_ar(cleanClientName)}' : ''),
                          style: const pw.TextStyle(fontSize: 5.5),
                        ),
                      ],
                    ),
                  ],
                ),

                // ── Row 3: barcode ──
                pw.Container(
                  height: 10,
                  alignment: pw.Alignment.center,
                  child: pw.BarcodeWidget(
                    barcode: pw.Barcode.code128(),
                    data: barData,
                    drawText: false,
                  ),
                ),
              ],
            ),
          );
        },
      );
    }

    // ── Step 3: generate pages ───────────────────────────────────────────────
    int globalWindowIndex = 0;
    int addedPagesCount = 0;

    for (final detail in _detailsList) {
      final detailId = detail['id'] as int;
      final gameName = detail['game']?.toString() ?? 'Window';
      final sashCount = _getSashCount(detail);

      final editorsList = _editors[detailId] ?? [];
      List<Map<String, dynamic>> instances = [];
      if (editorsList.isNotEmpty) {
        for (final ed in editorsList) {
          final w = int.tryParse(ed.widthCtrl.text) ?? (detail['largeur'] as int? ?? 0);
          final h = int.tryParse(ed.heightCtrl.text) ?? (detail['hauteur'] as int? ?? 0);
          final q = int.tryParse(ed.qtyCtrl.text) ?? 1;
          final pos = ed.positionCtrl.text.trim();
          instances.add({
            'width': w,
            'height': h,
            'qty': q,
            'position': pos,
          });
        }
      } else {
        final instancesJson = detail['instances_json'];
        if (instancesJson != null && instancesJson.toString().isNotEmpty) {
          try {
            final decoded = jsonDecode(instancesJson.toString()) as List<dynamic>;
            instances = decoded.map((e) => Map<String, dynamic>.from(e)).toList();
          } catch (_) {}
        }
      }
      if (instances.isEmpty) {
        instances.add({
          'width': detail['largeur'] as int? ?? 0,
          'height': detail['hauteur'] as int? ?? 0,
          'qty': detail['quantity'] as int? ?? 1,
          'position': '',
        });
      }

      // Compute glass dims once per detail (same model for all instances)
      final glassDimsRecord = await _getGlassDimensionsFromBom(detail);
      final String? detailGlassDimsStr = glassDimsRecord != null
          ? '${glassDimsRecord.gw}×${glassDimsRecord.gh} mm'
          : null;

      int instIndex = 0;
      for (final inst in instances) {
        final w = inst['width'] as int;
        final h = inst['height'] as int;
        final qty = inst['qty'] as int;
        final pos = inst['position']?.toString() ?? '';

        // Use the pre-computed glass dims from the detail level
        final String? glassDimsStr = detailGlassDimsStr;

        final bool isDetailMatch =
            targetDetailId == null || detailId == targetDetailId;
        final bool isInstanceMatch =
            targetInstanceIndex == null || instIndex == targetInstanceIndex;

        for (int k = 0; k < qty; k++) {
          globalWindowIndex++;

          if (!isDetailMatch || !isInstanceMatch) {
            continue;
          }
          if (targetWindowSubIndex != null &&
              (k + 1) != targetWindowSubIndex) {
            continue;
          }

          addedPagesCount++;
          final barBase = 'CMD-$orderId-D$detailId-W$globalWindowIndex';

          // ── Frame ticket ──
          pdf.addPage(buildStickerPage(
            windowNum: globalWindowIndex,
            pieceLabel: 'Cadre',
            w: w,
            h: h,
            pos: pos,
            gameName: gameName,
            barData: '$barBase-F',
            glassDims: glassDimsStr,
            siteName: projectName,
          ));

          // ── Sash tickets — same template, one per sash ──
          for (int s = 1; s <= sashCount; s++) {
            pdf.addPage(buildStickerPage(
              windowNum: globalWindowIndex,
              pieceLabel: 'Ouvrant $s',
              w: w,
              h: h,
              pos: pos,
              gameName: gameName,
              barData: '$barBase-S$s',
              glassDims: glassDimsStr,
              siteName: projectName,
            ));
          }
        }
        instIndex++;
      }
    }

    if (addedPagesCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد أي نوافذ لطباعة ملصقاتها!')),
      );
      return;
    }

    await Printing.layoutPdf(
      onLayout: (PdfPageFormat format) async => pdf.save(),
      name: 'Stickers-Order-$orderId.pdf',
      format: const PdfPageFormat(50 * PdfPageFormat.mm, 30 * PdfPageFormat.mm),
      dynamicLayout: false,
      usePrinterSettings: true,
    );
  }

  void _handlePrintInstance(int detailId, int instanceIndex, int quantity) {
    final detail = _detailsList.firstWhere((d) => d['id'] == detailId, orElse: () => <String, dynamic>{});
    if (detail.isEmpty) {
      return;
    }
    
    final editorsList = _editors[detailId] ?? [];
    if (instanceIndex >= editorsList.length) {
      return;
    }

    if (quantity > 1) {
      showDialog(
        context: context,
        builder: (ctx) {
          return AlertDialog(
            title: const Text('خيارات الطباعة', style: TextStyle(fontWeight: FontWeight.bold)),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(Icons.print_rounded, color: Colors.indigo),
                    title: const Text('طباعة كل النسخ'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _printStickers(targetDetailId: detailId, targetInstanceIndex: instanceIndex);
                    },
                  ),
                  const Divider(),
                  ...List.generate(quantity, (index) {
                    return ListTile(
                      leading: const Icon(Icons.qr_code_rounded, color: Colors.grey),
                      title: Text('طباعة النسخة رقم ${index + 1}'),
                      onTap: () {
                        Navigator.pop(ctx);
                        _printStickers(targetDetailId: detailId, targetInstanceIndex: instanceIndex, targetWindowSubIndex: index + 1);
                      },
                    );
                  }),
                ],
              ),
            ),
          );
        },
      );
    } else {
      _printStickers(targetDetailId: detailId, targetInstanceIndex: instanceIndex);
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isAr = lang == AppLanguage.arabic;
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBg = isDark ? const Color(0xFF1E1E1E) : Colors.white;
    final textColor = isDark ? Colors.white : Colors.black87;
    final subtextColor = isDark ? Colors.grey.shade300 : Colors.black54;

    return Directionality(
      textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: isDark ? const Color(0xFF121212) : const Color(0xFFF3F4F6),
        appBar: AppBar(
          backgroundColor: isDark ? const Color(0xFF1E1E1E) : Colors.indigo.shade800,
          title: Text(
            Localization.translate('تأكيد و تفصيل القياسات', lang),
            style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
          ),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.green.shade600,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              ),
              icon: const Icon(Icons.print_rounded),
              label: Text(Localization.translate('طباعة ملصقات الباركود', lang)),
              onPressed: _isLoading ? null : _printStickers,
            ),
            const SizedBox(width: 15),
          ],
        ),
        body: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : _detailsList.isEmpty
                ? Center(
                    child: Text(
                      Localization.translate('لا توجد عناصر في هذه الطلبية', lang),
                      style: TextStyle(fontSize: 16, color: subtextColor),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: _detailsList.length,
                    itemBuilder: (context, index) {
                      final detail = _detailsList[index];
                      final detailId = detail['id'] as int;
                      final totalQty = detail['quantity'] as int;
                      final gameName = detail['game']?.toString() ?? 'Window';
                      final imagePath = detail['drawing_image_path']?.toString();
                      final editorsList = _editors[detailId] ?? [];
                      final currentSum = _getSumQty(detailId);
                      final match = currentSum == totalQty;

                      return Card(
                        color: cardBg,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                          side: BorderSide(
                            color: match ? Colors.green.shade300 : Colors.red.shade300,
                            width: 1.5,
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 20),
                        elevation: 4,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              // Item Header
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Product thumbnail drawing
                                  if (imagePath != null && File(imagePath).existsSync())
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: Colors.grey.shade300),
                                        image: DecorationImage(
                                          image: FileImage(File(imagePath)),
                                          fit: BoxFit.cover,
                                        ),
                                      ),
                                    )
                                  else
                                    Container(
                                      width: 80,
                                      height: 80,
                                      decoration: BoxDecoration(
                                        borderRadius: BorderRadius.circular(10),
                                        color: isDark ? Colors.indigo.shade900.withValues(alpha: 0.4) : Colors.indigo.shade50,
                                        border: Border.all(color: isDark ? Colors.indigo.shade700 : Colors.indigo.shade100),
                                      ),
                                      child: Icon(Icons.window_rounded,
                                          size: 40, color: Colors.indigo.shade400),
                                    ),
                                  const SizedBox(width: 15),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          gameName,
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: textColor,
                                          ),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${Localization.translate('القياس', lang)}: ${detail['largeur']} × ${detail['hauteur']} mm',
                                          style: TextStyle(color: subtextColor),
                                        ),
                                        const SizedBox(height: 5),
                                        Text(
                                          '${Localization.translate('الكمية الإجمالية', lang)}: $totalQty',
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.indigo,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Match status badge
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: match ? Colors.green.shade50 : Colors.red.shade50,
                                      borderRadius: BorderRadius.circular(20),
                                      border: Border.all(
                                        color: match ? Colors.green : Colors.red,
                                      ),
                                    ),
                                    child: Text(
                                      '$currentSum / $totalQty',
                                      style: TextStyle(
                                        color: match ? Colors.green.shade800 : Colors.red.shade800,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 30),

                              // Instances input lists
                              Text(
                                'القياسات والمواقع التفصيلية للقطع:',
                                style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: textColor),
                              ),
                              const SizedBox(height: 10),

                              ListView.builder(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                itemCount: editorsList.length,
                                itemBuilder: (context, edIndex) {
                                  final ed = editorsList[edIndex];
                                  final isActive = _activeEditIndices[detailId] == edIndex;

                                  if (isActive) {
                                    // 🟢 Active editing layout: 2 rows of fields
                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 12),
                                      padding: const EdgeInsets.all(12),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF2C2C2C) : Colors.indigo.shade50.withValues(alpha: 0.5),
                                        borderRadius: BorderRadius.circular(12),
                                        border: Border.all(color: isDark ? Colors.indigo.shade700 : Colors.indigo.shade100, width: 1),
                                      ),
                                      child: Column(
                                        children: [
                                          // Line 1: Width & Height
                                          Row(
                                            children: [
                                              Expanded(
                                                child: TextFormField(
                                                  controller: ed.widthCtrl,
                                                  keyboardType: TextInputType.number,
                                                  style: TextStyle(color: textColor),
                                                  decoration: InputDecoration(
                                                    labelText: 'الطول / العرض (mm) *',
                                                    labelStyle: TextStyle(color: subtextColor),
                                                    border: const OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: TextFormField(
                                                  controller: ed.heightCtrl,
                                                  keyboardType: TextInputType.number,
                                                  style: TextStyle(color: textColor),
                                                  decoration: InputDecoration(
                                                    labelText: 'الارتفاع (mm) *',
                                                    labelStyle: TextStyle(color: subtextColor),
                                                    border: const OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                          const SizedBox(height: 10),
                                          // Line 2: Qty & Location & Delete Button
                                          Row(
                                            children: [
                                              Expanded(
                                                flex: 2,
                                                child: TextFormField(
                                                  controller: ed.qtyCtrl,
                                                  keyboardType: TextInputType.number,
                                                  style: TextStyle(color: textColor),
                                                  decoration: InputDecoration(
                                                    labelText: 'الكمية *',
                                                    labelStyle: TextStyle(color: subtextColor),
                                                    border: const OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                  onChanged: (_) {
                                                    setState(() {
                                                      final sum = _getSumQty(detailId);
                                                      if (sum >= totalQty) {
                                                        _activeEditIndices[detailId] = -1;
                                                      }
                                                    });
                                                  },
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                flex: 4,
                                                child: TextFormField(
                                                  controller: ed.positionCtrl,
                                                  style: TextStyle(color: textColor),
                                                  decoration: InputDecoration(
                                                    labelText: 'الموضع / الموقع',
                                                    labelStyle: TextStyle(color: subtextColor),
                                                    border: const OutlineInputBorder(),
                                                    isDense: true,
                                                  ),
                                                ),
                                              ),
                                              if (editorsList.length > 1) ...[
                                                const SizedBox(width: 8),
                                                IconButton(
                                                  icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent),
                                                  onPressed: () {
                                                    setState(() {
                                                      editorsList.removeAt(edIndex);
                                                      final sum = _getSumQty(detailId);
                                                      _activeEditIndices[detailId] = (sum >= totalQty) ? -1 : (editorsList.length - 1);
                                                    });
                                                  },
                                                ),
                                              ],
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(Icons.print_rounded, color: Colors.green),
                                                onPressed: () {
                                                  final qty = int.tryParse(ed.qtyCtrl.text) ?? 1;
                                                  _handlePrintInstance(detailId, edIndex, qty);
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    );
                                  } else {
                                    // 🟢 Collapsed layout: Single compact row description
                                    final wStr = ed.widthCtrl.text.isEmpty ? '0' : ed.widthCtrl.text;
                                    final hStr = ed.heightCtrl.text.isEmpty ? '0' : ed.heightCtrl.text;
                                    final qStr = ed.qtyCtrl.text.isEmpty ? '0' : ed.qtyCtrl.text;
                                    final posStr = ed.positionCtrl.text.trim().isEmpty ? '—' : ed.positionCtrl.text.trim();

                                    return Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: isDark ? const Color(0xFF262626) : Colors.white,
                                        borderRadius: BorderRadius.circular(10),
                                        border: Border.all(color: isDark ? Colors.grey.shade800 : Colors.grey.shade200),
                                      ),
                                      child: Row(
                                        children: [
                                          const Icon(Icons.check_circle_outline_rounded, color: Colors.green, size: 18),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Text(
                                              '$wStr × $hStr مم  ·  الكمية: $qStr  ·  الموقع: $posStr',
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.bold,
                                                color: textColor,
                                              ),
                                            ),
                                          ),
                                          IconButton(
                                            icon: const Icon(Icons.edit_rounded, color: Colors.blue, size: 20),
                                            onPressed: () {
                                              setState(() {
                                                _activeEditIndices[detailId] = edIndex;
                                              });
                                            },
                                          ),
                                          if (editorsList.length > 1)
                                            IconButton(
                                              icon: const Icon(Icons.delete_forever_rounded, color: Colors.redAccent, size: 20),
                                              onPressed: () {
                                                setState(() {
                                                  editorsList.removeAt(edIndex);
                                                  final sum = _getSumQty(detailId);
                                                  _activeEditIndices[detailId] = (sum >= totalQty) ? -1 : (editorsList.length - 1);
                                                });
                                              },
                                            ),
                                          IconButton(
                                            icon: const Icon(Icons.print_rounded, color: Colors.green, size: 20),
                                            onPressed: () {
                                              final qty = int.tryParse(ed.qtyCtrl.text) ?? 1;
                                              _handlePrintInstance(detailId, edIndex, qty);
                                            },
                                          ),
                                        ],
                                      ),
                                    );
                                  }
                                },
                              ),

                              // Actions for this card
                              SizedBox(
                                width: double.infinity,
                                child: Wrap(
                                  alignment: WrapAlignment.spaceBetween,
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    if (currentSum < totalQty) ...[
                                      TextButton.icon(
                                        icon: const Icon(Icons.add_circle_outline_rounded),
                                        label: const Text('إضافة تقسيم / قياس'),
                                        onPressed: () {
                                          setState(() {
                                            editorsList.add(InstanceEditor(
                                              widthCtrl: TextEditingController(
                                                  text: detail['largeur'].toString()),
                                              heightCtrl: TextEditingController(
                                                  text: detail['hauteur'].toString()),
                                              qtyCtrl: TextEditingController(text: '1'),
                                              positionCtrl: TextEditingController(),
                                            ));
                                            final sum = _getSumQty(detailId);
                                            _activeEditIndices[detailId] = (sum >= totalQty) ? -1 : (editorsList.length - 1);
                                          });
                                        },
                                      ),
                                    ],
                                    ElevatedButton.icon(
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.indigo,
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                                      ),
                                      icon: const Icon(Icons.save_rounded),
                                      label: const Text('حفظ القياسات'),
                                      onPressed: () => _saveInstances(detailId, totalQty),
                                    ),
                                    TextButton.icon(
                                      icon: const Icon(Icons.print_rounded, color: Colors.green),
                                      label: const Text('طباعة العنصر', style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                      onPressed: _isLoading ? null : () => _printStickers(targetDetailId: detailId),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
        bottomNavigationBar: _isLoading || _detailsList.isEmpty
            ? null
            : Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: theme.brightness == Brightness.dark ? const Color(0xFF1E293B) : Colors.white,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      blurRadius: 8,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: SafeArea(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.teal.shade700,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      elevation: 3,
                    ),
                    icon: const Icon(Icons.check_circle_rounded, size: 22),
                    label: Text(
                      _tr(
                        '✅ تأكيد جميع القياسات والانتقال المباشر لإسناد المهام 🚀',
                        '✅ Valider les mesures et passer à l\'affectation 🚀',
                        '✅ Confirm All Measurements & Go to Task Allocation 🚀',
                        lang,
                      ),
                      style: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    onPressed: () async {
                      // 1. Validate sums
                      bool allValid = true;
                      for (final detail in _detailsList) {
                        final detailId = detail['id'] as int;
                        final totalQty = detail['quantity'] as int;
                        final sum = _getSumQty(detailId);
                        if (sum != totalQty) {
                          allValid = false;
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              backgroundColor: Colors.redAccent,
                              content: Text(
                                'مجموع كميات القياسات للعنصر #$detailId ($sum) يجب أن يساوي الكمية الإجمالية ($totalQty)!',
                                style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                              ),
                            ),
                          );
                          break;
                        }
                      }

                      if (!allValid) return;

                      // 2. Save details to DB
                      for (final detail in _detailsList) {
                        final detailId = detail['id'] as int;
                        final list = _editors[detailId] ?? [];
                        final List<Map<String, dynamic>> data = [];
                        for (final ed in list) {
                          final w = int.tryParse(ed.widthCtrl.text) ?? 0;
                          final h = int.tryParse(ed.heightCtrl.text) ?? 0;
                          final q = int.tryParse(ed.qtyCtrl.text) ?? 0;
                          final pos = ed.positionCtrl.text.trim();
                          data.add({
                            'width': w,
                            'height': h,
                            'qty': q,
                            'position': pos,
                          });
                        }
                        final jsonStr = jsonEncode(data);
                        final myDb = await widget.db.db;
                        if (myDb != null) {
                          await myDb.update(
                            'Commandes_details',
                            {'instances_json': jsonStr},
                            where: 'id = ?',
                            whereArgs: [detailId],
                          );
                        }
                      }

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text(
                              '✅ تم حفظ وتأكيد القياسات بنجاح! الانتقال لإسناد المهام... 🚀',
                              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                            ),
                            backgroundColor: Colors.teal,
                            duration: Duration(seconds: 2),
                          ),
                        );

                        Navigator.pushReplacement(
                          context,
                          MaterialPageRoute(
                            builder: (_) => OrderAllocationScreen(
                              orderData: widget.orderData,
                              db: widget.db,
                            ),
                          ),
                        );
                      }
                    },
                  ),
                ),
              ),
      ),
    );
  }
}

class InstanceEditor {
  final TextEditingController widthCtrl;
  final TextEditingController heightCtrl;
  final TextEditingController qtyCtrl;
  final TextEditingController positionCtrl;

  InstanceEditor({
    required this.widthCtrl,
    required this.heightCtrl,
    required this.qtyCtrl,
    required this.positionCtrl,
  });
}
