import 'dart:convert';
import 'dart:io';
import 'package:database_data/widgets/app_material.dart';
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
import '../Screen/order_allocation_screen.dart';
import '../services/cloud_sync_service.dart';
import '../services/labels/label_print_service.dart';

int measurementQuantityValue(dynamic value, {int fallback = 0}) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '') ?? fallback;
}

/// Restores the editable measurement groups for a detail line. A legacy
/// order may contain one default instance with quantity 1 even when the line
/// itself is for several identical windows; that row is a draft, not a
/// partial confirmation, unless explicit confirmations were stored.
List<Map<String, dynamic>> normalizeMeasurementInstances({
  required int originalQuantity,
  required int originalWidth,
  required int originalHeight,
  required String defaultPosition,
  required List<dynamic> savedInstances,
  required List<dynamic> confirmedInstances,
}) {
  Map<String, dynamic> normalize(dynamic raw) {
    final value = raw is Map ? Map<String, dynamic>.from(raw) : const {};
    return {
      'width': measurementQuantityValue(
        value['width'] ?? value['largeur'],
        fallback: originalWidth,
      ),
      'height': measurementQuantityValue(
        value['height'] ?? value['hauteur'],
        fallback: originalHeight,
      ),
      'qty': measurementQuantityValue(value['qty'], fallback: 1),
      'position': (value['position'] ?? defaultPosition).toString(),
    };
  }

  List<Map<String, dynamic>> groupConfirmed() {
    final grouped = <String, Map<String, dynamic>>{};
    for (final raw in confirmedInstances) {
      final value = normalize(raw);
      final key = '${value['width']}-${value['height']}-${value['position']}';
      final existing = grouped[key];
      if (existing == null) {
        grouped[key] = {...value, 'qty': 1};
      } else {
        existing['qty'] = measurementQuantityValue(existing['qty']) + 1;
      }
    }
    return grouped.values.toList();
  }

  final restored = savedInstances
      .whereType<Map>()
      .map(normalize)
      .where((item) => measurementQuantityValue(item['qty']) > 0)
      .toList();
  final confirmed = groupConfirmed();

  if (restored.isEmpty && confirmed.isNotEmpty) return confirmed;
  if (restored.isEmpty) {
    return [
      {
        'width': originalWidth,
        'height': originalHeight,
        'qty': originalQuantity,
        'position': defaultPosition,
      },
    ];
  }

  final restoredQty = restored.fold<int>(
    0,
    (sum, item) => sum + measurementQuantityValue(item['qty']),
  );
  // Old drafts were written as one default row of quantity 1. Expand only
  // that shape to the ordered quantity; genuine partial confirmations always
  // have a non-empty confirmed list and therefore stay partial.
  if (confirmed.isEmpty && restored.length == 1 && restoredQty == 1) {
    restored.single['qty'] = originalQuantity;
  }
  return restored;
}

class OrderMeasurementsConfirmScreen extends StatefulWidget {
  final Map<String, dynamic> orderData;
  final SqlDatabase db;
  final int? initialDetailId;

  const OrderMeasurementsConfirmScreen({
    super.key,
    required this.orderData,
    required this.db,
    this.initialDetailId,
  });

  @override
  State<OrderMeasurementsConfirmScreen> createState() =>
      _OrderMeasurementsConfirmScreenState();
}

class _OrderMeasurementsConfirmScreenState
    extends State<OrderMeasurementsConfirmScreen> {
  bool _isLoading = true;
  bool _isSaving = false; // لمنع الضغط المزدوج على زر الحفظ
  bool _canLeaveScreen = false;
  final Set<int> _lockedDetails = {};

  bool get _allConfirmed =>
      _detailsList.isNotEmpty &&
      _detailsList.every((d) => _lockedDetails.contains(d['id']));
  List<Map<String, dynamic>> _detailsList = [];

  // Controllers maps: detailId -> list of instance editors
  final Map<int, List<InstanceEditor>> _editors = {};

  // Active edit index for each detailId
  final Map<int, int> _activeEditIndices = {};

  int _labelWidthMm = 50;

  PdfPageFormat get _labelPageFormat => PdfPageFormat(
    _labelWidthMm * PdfPageFormat.mm,
    30 * PdfPageFormat.mm,
    marginAll: 1 * PdfPageFormat.mm,
  );

  String _tr(String ar, String fr, String en, AppLanguage lang) {
    if (lang == AppLanguage.french) return fr;
    if (lang == AppLanguage.english) return en;
    return ar;
  }

  String _uiText(String ar, String fr, String en) {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    return _tr(ar, fr, en, language);
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
      final selectedIndex = _detailsList.indexWhere(
        (d) => d['id'] == widget.initialDetailId,
      );
      if (selectedIndex > 0) {
        _detailsList.insert(0, _detailsList.removeAt(selectedIndex));
      }

      for (final editors in _editors.values) {
        for (final editor in editors) {
          editor.dispose();
        }
      }
      _editors.clear();
      _lockedDetails.clear();
      for (final detail in _detailsList) {
        final detailId = detail['id'] as int;
        final originalQty = measurementQuantityValue(
          detail['quantity'],
          fallback: 1,
        ).clamp(1, 999999).toInt();
        final originalW = measurementQuantityValue(detail['largeur']);
        final originalH = measurementQuantityValue(detail['hauteur']);
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
        final confirmedJson = detail['confirmed_mesures_json'];
        List<dynamic> parsedInstances = [];
        List<dynamic> parsedConfirmed = [];
        if (instancesJson != null && instancesJson.toString().isNotEmpty) {
          try {
            parsedInstances =
                jsonDecode(instancesJson.toString()) as List<dynamic>;
          } catch (_) {}
        }
        if (confirmedJson != null && confirmedJson.toString().isNotEmpty) {
          try {
            final decoded = jsonDecode(confirmedJson.toString());
            if (decoded is List) parsedConfirmed = decoded;
          } catch (_) {}
        }

        if (parsedConfirmed.length == originalQty &&
            parsedConfirmed.every(
              (row) =>
                  row is Map &&
                  measurementQuantityValue(row['width'] ?? row['largeur']) >
                      0 &&
                  measurementQuantityValue(row['height'] ?? row['hauteur']) > 0,
            )) {
          _lockedDetails.add(detailId);
        }

        final List<InstanceEditor> editorsList = [];
        final normalizedInstances = normalizeMeasurementInstances(
          originalQuantity: originalQty,
          originalWidth: originalW,
          originalHeight: originalH,
          defaultPosition: defaultPos,
          savedInstances: _lockedDetails.contains(detailId)
              ? []
              : parsedInstances,
          confirmedInstances: parsedConfirmed,
        );
        for (final inst in normalizedInstances) {
          editorsList.add(
            InstanceEditor(
              widthCtrl: TextEditingController(text: inst['width'].toString()),
              heightCtrl: TextEditingController(
                text: inst['height'].toString(),
              ),
              qtyCtrl: TextEditingController(text: inst['qty'].toString()),
              positionCtrl: TextEditingController(
                text: inst['position']?.toString() ?? defaultPos,
              ),
            ),
          );
        }

        _editors[detailId] = editorsList;
        int initSum = 0;
        for (var ed in editorsList) {
          initSum += int.tryParse(ed.qtyCtrl.text) ?? 0;
        }
        _activeEditIndices[detailId] = (initSum >= originalQty)
            ? -1
            : (editorsList.length - 1);
      }

      setState(() {
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '${_uiText('خطأ أثناء تحميل البيانات', 'Erreur lors du chargement des données', 'Error loading data')}: $e',
          ),
        ),
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

  ({List<Map<String, dynamic>> instances, List<Map<String, dynamic>> confirmed})
  _measurementPayload(int detailId) {
    final instances = <Map<String, dynamic>>[];
    final confirmed = <Map<String, dynamic>>[];
    for (final ed in _editors[detailId] ?? const <InstanceEditor>[]) {
      final width = int.tryParse(ed.widthCtrl.text) ?? 0;
      final height = int.tryParse(ed.heightCtrl.text) ?? 0;
      final quantity = int.tryParse(ed.qtyCtrl.text) ?? 0;
      final position = ed.positionCtrl.text.trim();
      if (width <= 0 || height <= 0 || quantity <= 0) continue;

      instances.add({
        'width': width,
        'height': height,
        'qty': quantity,
        'position': position,
      });
      for (var index = 0; index < quantity; index++) {
        confirmed.add({
          'largeur': width,
          'hauteur': height,
          'width': width,
          'height': height,
          'position': position,
        });
      }
    }
    return (instances: instances, confirmed: confirmed);
  }

  Future<bool> _saveAllMeasurements() async {
    try {
      final myDb = await widget.db.db;
      if (myDb == null) return false;

      for (final detail in _detailsList) {
        final detailId = detail['id'] as int;
        final totalQuantity = measurementQuantityValue(
          detail['quantity'],
          fallback: 1,
        );
        final confirmedQuantity = _getSumQty(detailId);
        if (confirmedQuantity <= 0 || confirmedQuantity > totalQuantity) {
          return false;
        }
        final payload = _measurementPayload(detailId);
        if (payload.confirmed.length != confirmedQuantity) return false;
        await widget.db.updateCommandeDetailConfirmedMesures(
          detailId,
          jsonEncode(payload.instances),
          jsonEncode(payload.confirmed),
        );
      }

      // ⚡ استخدام notifyChange() بدل backupToCloud() الثقيل — الرفع يحدث في الخلفية
      CloudSyncService().notifyChange();

      return true;
    } catch (e) {
      debugPrint('Error saving all measurements: $e');
      return false;
    }
  }

  Future<void> _saveInstances(int detailId, int totalQty) async {
    final sum = _getSumQty(detailId);
    if (sum <= 0 || sum > totalQty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            _uiText(
              'الكمية المؤكدة ($sum) لا يمكن أن تتجاوز الكمية الإجمالية ($totalQty).',
              'La quantité confirmée ($sum) ne peut pas dépasser la quantité totale ($totalQty).',
              'Confirmed quantity ($sum) cannot exceed the total quantity ($totalQty).',
            ),
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
      );
      return;
    }
    final payload = _measurementPayload(detailId);
    if (payload.instances.isEmpty || payload.confirmed.length != sum) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: Colors.redAccent,
          content: Text(
            _uiText(
              'أدخل قياساً صحيحاً (عرض، ارتفاع، وكمية).',
              'Saisissez une mesure valide (largeur, hauteur et quantité).',
              'Enter a valid measurement (width, height, and quantity).',
            ),
          ),
        ),
      );
      return;
    }

    try {
      await widget.db.updateCommandeDetailConfirmedMesures(
        detailId,
        jsonEncode(payload.instances),
        jsonEncode(payload.confirmed),
      );
      await _loadDetails();
      if (mounted) {
        final remaining = totalQty - sum;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: remaining == 0 ? Colors.green : Colors.orange,
            content: Text(
              remaining == 0
                  ? _uiText(
                      'تم حفظ وتأكيد قياسات هذه النافذة ✅',
                      'Mesures de cette fenêtre enregistrées et confirmées ✅',
                      'This window’s measurements were saved and confirmed ✅',
                    )
                  : _uiText(
                      'تم حفظ $sum من $totalQty. بقي $remaining غير مؤكد وسيبقى ظاهراً في الرسم.',
                      '$sum sur $totalQty enregistrées. Il reste $remaining non confirmée, visible dans le dessin.',
                      '$sum of $totalQty saved. $remaining remains unconfirmed and visible in the drawing.',
                    ),
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              _uiText(
                'خطأ أثناء الحفظ: $e',
                'Erreur lors de l’enregistrement : $e',
                'Error while saving: $e',
              ),
            ),
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    for (final editors in _editors.values) {
      for (final editor in editors) {
        editor.dispose();
      }
    }
    super.dispose();
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
    Map<String, dynamic> detail,
  ) async {
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
      applyStoredOrderDetailColorToWindowModel(model, detail);

      // Run the same BOM computation used by material_consumption_screen
      final bomItems = ComponentCalculator.generateBom(model, {});

      // Find the first glass item with valid dimensions
      for (final item in bomItems) {
        if (item.category == 'glass' || item.category == 'panneau') {
          final w = item.length; // glass width in mm
          final h = item.glassHeight; // glass height in mm
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

  /// The measurement rows a detail prints stickers for: the rows on screen,
  /// else the saved draft, else the order line itself.
  List<Map<String, dynamic>> _stickerInstances(Map<String, dynamic> detail) {
    final width = measurementQuantityValue(detail['largeur']);
    final height = measurementQuantityValue(detail['hauteur']);
    final instances = <Map<String, dynamic>>[];
    for (final ed in _editors[detail['id']] ?? const <InstanceEditor>[]) {
      instances.add({
        'width': int.tryParse(ed.widthCtrl.text) ?? width,
        'height': int.tryParse(ed.heightCtrl.text) ?? height,
        'qty': int.tryParse(ed.qtyCtrl.text) ?? 1,
        'position': ed.positionCtrl.text.trim(),
      });
    }
    if (instances.isEmpty) {
      final instancesJson = detail['instances_json'];
      if (instancesJson != null && instancesJson.toString().isNotEmpty) {
        try {
          final decoded = jsonDecode(instancesJson.toString());
          if (decoded is List) {
            instances.addAll(
              decoded.whereType<Map>().map(Map<String, dynamic>.from),
            );
          }
        } catch (_) {}
      }
    }
    if (instances.isEmpty) {
      instances.add({
        'width': width,
        'height': height,
        'qty': measurementQuantityValue(detail['quantity'], fallback: 1),
        'position': '',
      });
    }
    return instances;
  }

  Future<void> _printStickers({
    int? targetDetailId,
    int? targetInstanceIndex,
    int? targetWindowSubIndex,
  }) async {
    final clientName =
        widget.orderData['client_name']?.toString() ??
        widget.orderData['client_display']?.toString() ??
        '${widget.orderData['firstname'] ?? ''} ${widget.orderData['lastname'] ?? ''}'
            .trim();
    final cleanClientName = clientName.isNotEmpty ? clientName : 'Client';
    final projectName = widget.orderData['project_name']?.toString() ?? '';
    final orderId = widget.orderData['id'] as int;
    // Database ids can become very large after synchronisation/imports. The
    // printed order number must remain the human-readable sequence (43, 44,
    // 45…) rather than a cumulative window or internal database id.
    final orderSequenceNumber = await widget.db.getOrderSequenceNumber(orderId);
    final labelPageFormat = _labelPageFormat;

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
    // Use the same rows as the printed pages; the saved instances_json can
    // differ from what is on screen and made "N / total" disagree.
    int totalWindowCount = 0;
    for (final detail in _detailsList) {
      for (final inst in _stickerInstances(detail)) {
        totalWindowCount += measurementQuantityValue(inst['qty']);
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
      return pw.Page(
        pageFormat: labelPageFormat,
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
                          'CMD #$orderSequenceNumber',
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
                          '${w}×${h} mm' +
                              (pos.isNotEmpty ? ' - ${_ar(pos)}' : ''),
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
                          'CMD #$orderSequenceNumber' +
                              (showClientAtBottom
                                  ? ' | ${_ar(cleanClientName)}'
                                  : ''),
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
      final instances = _stickerInstances(detail);

      // Compute glass dims once per detail (same model for all instances)
      final glassDimsRecord = await _getGlassDimensionsFromBom(detail);
      final String? detailGlassDimsStr = glassDimsRecord != null
          ? '${glassDimsRecord.gw}×${glassDimsRecord.gh} mm'
          : null;

      int instIndex = 0;
      for (final inst in instances) {
        final w = measurementQuantityValue(inst['width']);
        final h = measurementQuantityValue(inst['height']);
        final qty = measurementQuantityValue(inst['qty']);
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
          if (targetWindowSubIndex != null && (k + 1) != targetWindowSubIndex) {
            continue;
          }

          addedPagesCount++;
          final barBase = 'CMD-$orderId-D$detailId-W$globalWindowIndex';

          // ── Frame ticket ──
          pdf.addPage(
            buildStickerPage(
              windowNum: globalWindowIndex,
              pieceLabel: 'Cadre',
              w: w,
              h: h,
              pos: pos,
              gameName: gameName,
              barData: '$barBase-F',
              glassDims: glassDimsStr,
              siteName: projectName,
            ),
          );

          // ── Sash tickets — same template, one per sash ──
          for (int s = 1; s <= sashCount; s++) {
            pdf.addPage(
              buildStickerPage(
                windowNum: globalWindowIndex,
                pieceLabel: 'Ouvrant $s',
                w: w,
                h: h,
                pos: pos,
                gameName: gameName,
                barData: '$barBase-S$s',
                glassDims: glassDimsStr,
                siteName: projectName,
              ),
            );
          }
        }
        instIndex++;
      }
    }

    if (addedPagesCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _uiText(
              'لا توجد أي نوافذ لطباعة ملصقاتها!',
              'Aucune fenêtre disponible pour imprimer des étiquettes !',
              'There are no windows available to print labels for!',
            ),
          ),
        ),
      );
      return;
    }

    try {
      // The system dialog, or ZPL straight to the label printer.
      await LabelPrintService.printLabels(
        pdf,
        name: 'Stickers-Order-$orderSequenceNumber.pdf',
        format: labelPageFormat,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.green.shade700,
            content: Text(
              _uiText(
                'تم إرسال $addedPagesCount تيكيت إلى الطابعة (${_labelWidthMm}×30 مم).',
                '$addedPagesCount étiquettes envoyées à l’imprimante (${_labelWidthMm}×30 mm).',
                '$addedPagesCount labels sent to the printer (${_labelWidthMm}×30 mm).',
              ),
            ),
          ),
        );
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            backgroundColor: Colors.redAccent,
            content: Text(
              _uiText(
                'تعذر إرسال التيكيت إلى الطابعة: $error',
                'Impossible d’envoyer l’étiquette à l’imprimante : $error',
                'Could not send the label to the printer: $error',
              ),
            ),
          ),
        );
      }
    }
  }

  void _handlePrintInstance(int detailId, int instanceIndex, int quantity) {
    final detail = _detailsList.firstWhere(
      (d) => d['id'] == detailId,
      orElse: () => <String, dynamic>{},
    );
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
            title: Text(
              _uiText(
                'خيارات الطباعة',
                'Options d’impression',
                'Print options',
              ),
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: ListView(
                shrinkWrap: true,
                children: [
                  ListTile(
                    leading: const Icon(
                      Icons.print_rounded,
                      color: Colors.indigo,
                    ),
                    title: Text(
                      _uiText(
                        'طباعة كل النسخ',
                        'Imprimer toutes les copies',
                        'Print all copies',
                      ),
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      _printStickers(
                        targetDetailId: detailId,
                        targetInstanceIndex: instanceIndex,
                      );
                    },
                  ),
                  const Divider(),
                  ...List.generate(quantity, (index) {
                    return ListTile(
                      leading: const Icon(
                        Icons.qr_code_rounded,
                        color: Colors.grey,
                      ),
                      title: Text(
                        _uiText(
                          'طباعة النسخة رقم ${index + 1}',
                          'Imprimer la copie n° ${index + 1}',
                          'Print copy #${index + 1}',
                        ),
                      ),
                      onTap: () {
                        Navigator.pop(ctx);
                        _printStickers(
                          targetDetailId: detailId,
                          targetInstanceIndex: instanceIndex,
                          targetWindowSubIndex: index + 1,
                        );
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
      _printStickers(
        targetDetailId: detailId,
        targetInstanceIndex: instanceIndex,
      );
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

    return PopScope(
      canPop: !_isSaving && (_allConfirmed || _canLeaveScreen),
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop || _isSaving) return;
        final leave = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(
              _tr(
                'الخروج دون تأكيد؟',
                'Quitter sans confirmer ?',
                'Leave without confirming?',
                lang,
              ),
            ),
            content: Text(
              _tr(
                'لن تُحفظ التغييرات غير المؤكدة.',
                'Les modifications non confirmées ne seront pas enregistrées.',
                'Unconfirmed changes will not be saved.',
                lang,
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: Text(
                  _tr('متابعة', 'Continuer', 'Continue editing', lang),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text(_tr('خروج', 'Quitter', 'Leave', lang)),
              ),
            ],
          ),
        );
        if (leave == true && mounted) {
          setState(() => _canLeaveScreen = true);
          Navigator.of(this.context).pop();
        }
      },
      child: Directionality(
        textDirection: isAr ? TextDirection.rtl : TextDirection.ltr,
        child: Scaffold(
          backgroundColor: isDark
              ? const Color(0xFF121212)
              : const Color(0xFFF3F4F6),
          appBar: AppBar(
            backgroundColor: isDark
                ? const Color(0xFF1E1E1E)
                : Colors.indigo.shade800,
            title: Text(
              Localization.translate('تأكيد و تفصيل القياسات', lang),
              style: const TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.white,
              ),
            ),
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              PopupMenuButton<int>(
                icon: const Icon(Icons.straighten_rounded, color: Colors.white),
                tooltip: _tr(
                  'مقاس التيكيت: ${_labelWidthMm}×30 مم',
                  'Format de l’étiquette : ${_labelWidthMm}×30 mm',
                  'Label size: ${_labelWidthMm}×30 mm',
                  lang,
                ),
                onSelected: (width) => setState(() => _labelWidthMm = width),
                itemBuilder: (context) => [
                  CheckedPopupMenuItem(
                    value: 50,
                    checked: _labelWidthMm == 50,
                    child: Text(
                      _tr(
                        'تيكيت صغير 50 × 30 مم',
                        'Petite étiquette 50 × 30 mm',
                        'Small label 50 × 30 mm',
                        lang,
                      ),
                    ),
                  ),
                  CheckedPopupMenuItem(
                    value: 70,
                    checked: _labelWidthMm == 70,
                    child: Text(
                      _tr(
                        'تيكيت صغير 70 × 30 مم',
                        'Petite étiquette 70 × 30 mm',
                        'Small label 70 × 30 mm',
                        lang,
                      ),
                    ),
                  ),
                ],
              ),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                icon: const Icon(Icons.print_rounded),
                label: Text(
                  Localization.translate('طباعة ملصقات الباركود', lang),
                ),
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
                    Localization.translate(
                      'لا توجد عناصر في هذه الطلبية',
                      lang,
                    ),
                    style: TextStyle(fontSize: 16, color: subtextColor),
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _detailsList.length,
                  itemBuilder: (context, index) {
                    final detail = _detailsList[index];
                    final detailId = detail['id'] as int;
                    final totalQty = measurementQuantityValue(
                      detail['quantity'],
                      fallback: 1,
                    );
                    final gameName = detail['game']?.toString() ?? 'Window';
                    final imagePath = detail['drawing_image_path']?.toString();
                    final editorsList = _editors[detailId] ?? [];
                    final currentSum = _getSumQty(detailId);
                    final locked = _lockedDetails.contains(detailId);
                    final match = currentSum == totalQty;

                    return Card(
                      color: cardBg,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(15),
                        side: BorderSide(
                          color: match
                              ? Colors.green.shade300
                              : Colors.red.shade300,
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
                                if (imagePath != null &&
                                    File(imagePath).existsSync())
                                  Container(
                                    width: 80,
                                    height: 80,
                                    decoration: BoxDecoration(
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: Colors.grey.shade300,
                                      ),
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
                                      color: isDark
                                          ? Colors.indigo.shade900.withValues(
                                              alpha: 0.4,
                                            )
                                          : Colors.indigo.shade50,
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.indigo.shade700
                                            : Colors.indigo.shade100,
                                      ),
                                    ),
                                    child: Icon(
                                      Icons.window_rounded,
                                      size: 40,
                                      color: Colors.indigo.shade400,
                                    ),
                                  ),
                                const SizedBox(width: 15),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
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
                                    horizontal: 10,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: match
                                        ? Colors.green.shade50
                                        : Colors.red.shade50,
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: match ? Colors.green : Colors.red,
                                    ),
                                  ),
                                  child: Text(
                                    '$currentSum / $totalQty',
                                    style: TextStyle(
                                      color: match
                                          ? Colors.green.shade800
                                          : Colors.red.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const Divider(height: 30),

                            if (!match) ...[
                              Container(
                                width: double.infinity,
                                margin: const EdgeInsets.only(bottom: 12),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 12,
                                  vertical: 10,
                                ),
                                decoration: BoxDecoration(
                                  color: Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(
                                    color: Colors.amber.shade700,
                                  ),
                                ),
                                child: Text(
                                  currentSum < totalQty
                                      ? _tr(
                                          'تم تأكيد $currentSum من $totalQty. بقي ${totalQty - currentSum} غير مؤكد وسيبقى في الرسم.',
                                          '$currentSum sur $totalQty confirmées. Il reste ${totalQty - currentSum} non confirmée, visible dans le dessin.',
                                          '$currentSum of $totalQty confirmed. ${totalQty - currentSum} remains unconfirmed and visible in the drawing.',
                                          lang,
                                        )
                                      : _tr(
                                          'الكمية المؤكدة ($currentSum) أكبر من الكمية المطلوبة ($totalQty).',
                                          'La quantité confirmée ($currentSum) est supérieure à la quantité demandée ($totalQty).',
                                          'Confirmed quantity ($currentSum) is greater than requested quantity ($totalQty).',
                                          lang,
                                        ),
                                  style: TextStyle(
                                    color: Colors.amber.shade900,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],

                            // Instances input lists
                            Text(
                              _tr(
                                'القياسات والمواقع التفصيلية للقطع:',
                                'Mesures et emplacements détaillés :',
                                'Detailed measurements and locations:',
                                lang,
                              ),
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                                color: textColor,
                              ),
                            ),
                            const SizedBox(height: 10),

                            ListView.builder(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: editorsList.length,
                              itemBuilder: (context, edIndex) {
                                final ed = editorsList[edIndex];
                                final isActive =
                                    !locked &&
                                    _activeEditIndices[detailId] == edIndex;

                                if (isActive) {
                                  // 🟢 Active editing layout: 2 rows of fields
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 12),
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF2C2C2C)
                                          : Colors.indigo.shade50.withValues(
                                              alpha: 0.5,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.indigo.shade700
                                            : Colors.indigo.shade100,
                                        width: 1,
                                      ),
                                    ),
                                    child: Column(
                                      children: [
                                        // Line 1: Width & Height
                                        Row(
                                          children: [
                                            Expanded(
                                              child: TextFormField(
                                                controller: ed.widthCtrl,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: TextStyle(
                                                  color: textColor,
                                                ),
                                                decoration: InputDecoration(
                                                  labelText: _tr(
                                                    'العرض (مم) *',
                                                    'Largeur (mm) *',
                                                    'Width (mm) *',
                                                    lang,
                                                  ),
                                                  labelStyle: TextStyle(
                                                    color: subtextColor,
                                                  ),
                                                  border:
                                                      const OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: TextFormField(
                                                controller: ed.heightCtrl,
                                                keyboardType:
                                                    TextInputType.number,
                                                style: TextStyle(
                                                  color: textColor,
                                                ),
                                                decoration: InputDecoration(
                                                  labelText: _tr(
                                                    'الارتفاع (مم) *',
                                                    'Hauteur (mm) *',
                                                    'Height (mm) *',
                                                    lang,
                                                  ),
                                                  labelStyle: TextStyle(
                                                    color: subtextColor,
                                                  ),
                                                  border:
                                                      const OutlineInputBorder(),
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
                                                keyboardType:
                                                    TextInputType.number,
                                                style: TextStyle(
                                                  color: textColor,
                                                ),
                                                decoration: InputDecoration(
                                                  labelText: _tr(
                                                    'الكمية *',
                                                    'Quantité *',
                                                    'Quantity *',
                                                    lang,
                                                  ),
                                                  labelStyle: TextStyle(
                                                    color: subtextColor,
                                                  ),
                                                  border:
                                                      const OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                                onChanged: (_) {
                                                  setState(() {
                                                    final sum = _getSumQty(
                                                      detailId,
                                                    );
                                                    if (sum >= totalQty) {
                                                      _activeEditIndices[detailId] =
                                                          -1;
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
                                                style: TextStyle(
                                                  color: textColor,
                                                ),
                                                decoration: InputDecoration(
                                                  labelText: _tr(
                                                    'الموضع / الموقع',
                                                    'Position / emplacement',
                                                    'Position / location',
                                                    lang,
                                                  ),
                                                  labelStyle: TextStyle(
                                                    color: subtextColor,
                                                  ),
                                                  border:
                                                      const OutlineInputBorder(),
                                                  isDense: true,
                                                ),
                                              ),
                                            ),
                                            if (!locked &&
                                                editorsList.length > 1) ...[
                                              const SizedBox(width: 8),
                                              IconButton(
                                                icon: const Icon(
                                                  Icons.delete_forever_rounded,
                                                  color: Colors.redAccent,
                                                ),
                                                onPressed: () {
                                                  setState(() {
                                                    editorsList.removeAt(
                                                      edIndex,
                                                    );
                                                    final sum = _getSumQty(
                                                      detailId,
                                                    );
                                                    _activeEditIndices[detailId] =
                                                        (sum >= totalQty)
                                                        ? -1
                                                        : (editorsList.length -
                                                              1);
                                                  });
                                                },
                                              ),
                                            ],
                                            const SizedBox(width: 8),
                                            IconButton(
                                              icon: const Icon(
                                                Icons.print_rounded,
                                                color: Colors.green,
                                              ),
                                              onPressed: () {
                                                final qty =
                                                    int.tryParse(
                                                      ed.qtyCtrl.text,
                                                    ) ??
                                                    1;
                                                _handlePrintInstance(
                                                  detailId,
                                                  edIndex,
                                                  qty,
                                                );
                                              },
                                            ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  );
                                } else {
                                  // 🟢 Collapsed layout: Single compact row description
                                  final wStr = ed.widthCtrl.text.isEmpty
                                      ? '0'
                                      : ed.widthCtrl.text;
                                  final hStr = ed.heightCtrl.text.isEmpty
                                      ? '0'
                                      : ed.heightCtrl.text;
                                  final qStr = ed.qtyCtrl.text.isEmpty
                                      ? '0'
                                      : ed.qtyCtrl.text;
                                  final posStr =
                                      ed.positionCtrl.text.trim().isEmpty
                                      ? '—'
                                      : ed.positionCtrl.text.trim();

                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 8),
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 10,
                                      vertical: 8,
                                    ),
                                    decoration: BoxDecoration(
                                      color: isDark
                                          ? const Color(0xFF262626)
                                          : Colors.white,
                                      borderRadius: BorderRadius.circular(10),
                                      border: Border.all(
                                        color: isDark
                                            ? Colors.grey.shade800
                                            : Colors.grey.shade200,
                                      ),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(
                                          Icons.check_circle_outline_rounded,
                                          color: Colors.green,
                                          size: 18,
                                        ),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            _tr(
                                              '$wStr × $hStr مم  ·  الكمية: $qStr  ·  الموقع: $posStr',
                                              '$wStr × $hStr mm  ·  Quantité : $qStr  ·  Emplacement : $posStr',
                                              '$wStr × $hStr mm  ·  Quantity: $qStr  ·  Location: $posStr',
                                              lang,
                                            ),
                                            style: TextStyle(
                                              fontSize: 13,
                                              fontWeight: FontWeight.bold,
                                              color: textColor,
                                            ),
                                          ),
                                        ),
                                        if (!locked)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.edit_rounded,
                                              color: Colors.blue,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                _activeEditIndices[detailId] =
                                                    edIndex;
                                              });
                                            },
                                          ),
                                        if (!locked && editorsList.length > 1)
                                          IconButton(
                                            icon: const Icon(
                                              Icons.delete_forever_rounded,
                                              color: Colors.redAccent,
                                              size: 20,
                                            ),
                                            onPressed: () {
                                              setState(() {
                                                editorsList.removeAt(edIndex);
                                                final sum = _getSumQty(
                                                  detailId,
                                                );
                                                _activeEditIndices[detailId] =
                                                    (sum >= totalQty)
                                                    ? -1
                                                    : (editorsList.length - 1);
                                              });
                                            },
                                          ),
                                        IconButton(
                                          icon: const Icon(
                                            Icons.print_rounded,
                                            color: Colors.green,
                                            size: 20,
                                          ),
                                          onPressed: () {
                                            final qty =
                                                int.tryParse(ed.qtyCtrl.text) ??
                                                1;
                                            _handlePrintInstance(
                                              detailId,
                                              edIndex,
                                              qty,
                                            );
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
                                  if (!locked && currentSum < totalQty) ...[
                                    TextButton.icon(
                                      icon: const Icon(
                                        Icons.add_circle_outline_rounded,
                                      ),
                                      label: Text(
                                        _tr(
                                          'إضافة تقسيم / قياس',
                                          'Ajouter une répartition / mesure',
                                          'Add split / measurement',
                                          lang,
                                        ),
                                      ),
                                      onPressed: () {
                                        setState(() {
                                          editorsList.add(
                                            InstanceEditor(
                                              widthCtrl: TextEditingController(
                                                text: detail['largeur']
                                                    .toString(),
                                              ),
                                              heightCtrl: TextEditingController(
                                                text: detail['hauteur']
                                                    .toString(),
                                              ),
                                              qtyCtrl: TextEditingController(
                                                text: '1',
                                              ),
                                              positionCtrl:
                                                  TextEditingController(),
                                            ),
                                          );
                                          final sum = _getSumQty(detailId);
                                          _activeEditIndices[detailId] =
                                              (sum >= totalQty)
                                              ? -1
                                              : (editorsList.length - 1);
                                        });
                                      },
                                    ),
                                  ],
                                  if (locked)
                                    TextButton.icon(
                                      icon: const Icon(Icons.edit_rounded),
                                      label: Text(
                                        _tr('تعديل', 'Modifier', 'Edit', lang),
                                      ),
                                      onPressed: () => setState(() {
                                        _lockedDetails.remove(detailId);
                                        _activeEditIndices[detailId] = -1;
                                      }),
                                    ),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: Colors.indigo,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 16,
                                        vertical: 10,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                    ),
                                    icon: const Icon(Icons.save_rounded),
                                    label: Text(
                                      _tr(
                                        locked
                                            ? 'القياسات مؤكدة'
                                            : 'تأكيد القياسات',
                                        locked
                                            ? 'Mesures confirmées'
                                            : 'Confirmer les mesures',
                                        locked
                                            ? 'Measurements confirmed'
                                            : 'Confirm measurements',
                                        lang,
                                      ),
                                    ),
                                    onPressed: locked || _isSaving
                                        ? null
                                        : () async {
                                            setState(() => _isSaving = true);
                                            await _saveInstances(
                                              detailId,
                                              totalQty,
                                            );
                                            if (mounted)
                                              setState(() => _isSaving = false);
                                          },
                                  ),
                                  TextButton.icon(
                                    icon: const Icon(
                                      Icons.print_rounded,
                                      color: Colors.green,
                                    ),
                                    label: Text(
                                      _tr(
                                        'طباعة العنصر',
                                        'Imprimer l’élément',
                                        'Print item',
                                        lang,
                                      ),
                                      style: TextStyle(
                                        color: Colors.green,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    onPressed: _isLoading
                                        ? null
                                        : () => _printStickers(
                                            targetDetailId: detailId,
                                          ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                  decoration: BoxDecoration(
                    color: theme.brightness == Brightness.dark
                        ? const Color(0xFF1E293B)
                        : Colors.white,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.12),
                        blurRadius: 10,
                        offset: const Offset(0, -3),
                      ),
                    ],
                  ),
                  child: SafeArea(
                    child: SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.teal.shade700,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                          elevation: 4,
                        ),
                        icon: _isSaving
                            ? const SizedBox(
                                width: 22,
                                height: 22,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2.5,
                                ),
                              )
                            : const Icon(Icons.check_circle_rounded, size: 24),
                        label: Text(
                          _isSaving
                              ? _tr(
                                  'جاري الحفظ...',
                                  'Enregistrement...',
                                  'Saving...',
                                  lang,
                                )
                              : _tr(
                                  _allConfirmed
                                      ? 'كل القياسات مؤكدة'
                                      : 'تأكيد كل القياسات',
                                  _allConfirmed
                                      ? 'Toutes les mesures sont confirmées'
                                      : 'Confirmer toutes les mesures',
                                  _allConfirmed
                                      ? 'All measurements confirmed'
                                      : 'Confirm all measurements',
                                  lang,
                                ),
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: _allConfirmed || _isSaving
                            ? null
                            : () async {
                                // 1. Validate sums
                                bool allValid = true;
                                for (final detail in _detailsList) {
                                  final detailId = detail['id'] as int;
                                  final totalQty = measurementQuantityValue(
                                    detail['quantity'],
                                    fallback: 1,
                                  );
                                  final sum = _getSumQty(detailId);
                                  if (sum != totalQty) {
                                    allValid = false;
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        backgroundColor: Colors.redAccent,
                                        content: Text(
                                          _tr(
                                            sum < totalQty
                                                ? 'القياسات غير مكتملة للعنصر #$detailId: تم تأكيد $sum من $totalQty، وبقي ${totalQty - sum} في الرسم.'
                                                : 'مجموع كميات القياسات للعنصر #$detailId ($sum) أكبر من الكمية الإجمالية ($totalQty)!',
                                            sum < totalQty
                                                ? 'Mesures incomplètes (#$detailId) : $sum sur $totalQty confirmées, il reste ${totalQty - sum} dans le dessin.'
                                                : 'La somme des quantités (#$detailId: $sum) dépasse le total ($totalQty) !',
                                            sum < totalQty
                                                ? 'Measurements are incomplete for item #$detailId: $sum of $totalQty confirmed; ${totalQty - sum} remain in the drawing.'
                                                : 'Total quantity sum (#$detailId: $sum) exceeds ($totalQty)!',
                                            lang,
                                          ),
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ),
                                    );
                                    break;
                                  }
                                }

                                if (!allValid) return;

                                // 2. حفظ محلي سريع بدون انتظار السحابة
                                if (_isSaving) return;
                                setState(() => _isSaving = true);
                                final saved = await _saveAllMeasurements();
                                if (!mounted) return;
                                setState(() => _isSaving = false);

                                if (saved) {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(
                                        _tr(
                                          '✅ تم حفظ القياسات',
                                          '✅ Les mesures ont été enregistrées avec succès',
                                          '✅ All measurements saved',
                                          lang,
                                        ),
                                        style: const TextStyle(
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      backgroundColor: Colors.teal,
                                      duration: const Duration(seconds: 2),
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
                                } else {
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      backgroundColor: Colors.redAccent,
                                      content: Text(
                                        _tr(
                                          'تعذر حفظ القياسات. أعد المحاولة وتحقق من البيانات.',
                                          'Impossible d’enregistrer les mesures. Réessayez et vérifiez les données.',
                                          'Could not save measurements. Try again and check the data.',
                                          lang,
                                        ),
                                      ),
                                    ),
                                  );
                                }
                              },
                      ),
                    ),
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

  void dispose() {
    widthCtrl.dispose();
    heightCtrl.dispose();
    qtyCtrl.dispose();
    positionCtrl.dispose();
  }

  InstanceEditor({
    required this.widthCtrl,
    required this.heightCtrl,
    required this.qtyCtrl,
    required this.positionCtrl,
  });
}
