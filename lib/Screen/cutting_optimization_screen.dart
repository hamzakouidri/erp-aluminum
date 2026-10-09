import 'dart:convert';
import 'dart:isolate';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';
import 'package:database_data/sql_database.dart';
import 'package:database_data/Commande/Systeme/model.dart';
import 'package:database_data/Commande/Systeme/model_serialization.dart';
import 'package:database_data/Commande/Systeme/calculate_component.dart';
import 'package:database_data/Commande/Systeme/cutting_settings.dart';
import 'package:database_data/services/cutting_optimizer_engine.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import '../services/pdf_font_cache.dart';
import '../Commande/order_measurements_confirm_screen.dart';
import '../widgets/auto_scroll_expansion_tile.dart';

enum OptimizationMode {
  singleOrder, // 1. طلبية كاملة
  multipleOrders, // 2. عدة طلبيات
  orderRange, // 3. جزء من طلبية لغاية النهاية
  customElements, // 4. عناصر مختارة من طلبيات مختلفة
}

class CuttingOptimizationScreen extends StatefulWidget {
  final SqlDatabase db;
  final int? initialOrderId;

  const CuttingOptimizationScreen({
    super.key,
    required this.db,
    this.initialOrderId,
  });

  @override
  State<CuttingOptimizationScreen> createState() =>
      _CuttingOptimizationScreenState();
}

class _CuttingOptimizationScreenState extends State<CuttingOptimizationScreen>
    with SingleTickerProviderStateMixin {
  OptimizationMode _selectedMode = OptimizationMode.singleOrder;
  bool _isLoadingOrders = true;
  bool _isOptimizing = false;

  List<Map<String, dynamic>> _allOrders = [];
  Map<int, List<Map<String, dynamic>>> _orderDetailsCache = {};

  // Mode 1: Single Order
  int? _selectedOrderId;

  // Mode 2: Multiple Orders
  final Set<int> _selectedOrderIds = {};

  // Mode 3: Order Range
  int? _rangeOrderId;
  int _rangeStartItemIndex = 1;
  int? _rangeEndItemIndex;

  // Mode 4: Custom Elements
  final Set<int> _selectedDetailIds = {};
  final Map<int, int> _detailBatchQuantities = {};
  int _optimizationGeneration = 0;

  // Optimization Parameters
  double _barLengthMm = 6000.0;
  double _sawKerfMm = CuttingSettings.sawKerfMm;
  double _chuteThresholdMm = 800.0;

  // Optimization Results
  CuttingOptimizationReport? _report;
  String _selectedProfileFilter = 'الكل';
  late final TabController _mobileTabController;

  @override
  void initState() {
    super.initState();
    _mobileTabController = TabController(length: 2, vsync: this);
    _selectedOrderId = widget.initialOrderId;
    _rangeOrderId = widget.initialOrderId;
    if (widget.initialOrderId != null) {
      _selectedOrderIds.add(widget.initialOrderId!);
    }
    _loadOrders();
  }

  @override
  void dispose() {
    _mobileTabController.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() => _isLoadingOrders = true);
    try {
      final orders = await widget.db.readCommandesWithClients();
      final active = orders.where((o) {
        final isDeleted = o['is_deleted'] == 1;
        return !isDeleted;
      }).toList();

      if (mounted) {
        setState(() {
          _allOrders = active;
          if (_selectedOrderId == null && active.isNotEmpty) {
            _selectedOrderId = (active.first['id'] as num?)?.toInt();
            _rangeOrderId = _selectedOrderId;
          }
          _isLoadingOrders = false;
        });
        if (_selectedOrderId != null) {
          _loadDetailsForOrder(_selectedOrderId!);
          _runOptimization();
        }
      }
    } catch (e) {
      debugPrint('Error loading orders: $e');
      if (mounted) setState(() => _isLoadingOrders = false);
    }
  }

  Future<List<Map<String, dynamic>>> _loadDetailsForOrder(int orderId) async {
    if (_orderDetailsCache.containsKey(orderId)) {
      return _orderDetailsCache[orderId]!;
    }
    try {
      final details = await widget.db.readCommandeDetails(orderId);
      _orderDetailsCache[orderId] = details;
      return details;
    } catch (e) {
      debugPrint('Error loading details for order $orderId: $e');
      return [];
    }
  }

  Future<void> _runOptimization() async {
    final generation = ++_optimizationGeneration;
    setState(() => _isOptimizing = true);

    try {
      final List<CuttingPiece> pieces = [];

      switch (_selectedMode) {
        case OptimizationMode.singleOrder:
          if (_selectedOrderId != null) {
            final details = await _loadDetailsForOrder(_selectedOrderId!);
            final orderName = _getOrderName(_selectedOrderId!);
            for (final d in details) {
              pieces.addAll(
                _extractPiecesFromDetail(
                  d,
                  _selectedOrderId!,
                  orderName,
                  quantityOverride: _batchQuantityForDetail(d),
                ),
              );
              await Future<void>.delayed(Duration.zero);
            }
          }
          break;

        case OptimizationMode.multipleOrders:
          for (final oId in _selectedOrderIds) {
            final details = await _loadDetailsForOrder(oId);
            final orderName = _getOrderName(oId);
            for (final d in details) {
              pieces.addAll(
                _extractPiecesFromDetail(
                  d,
                  oId,
                  orderName,
                  quantityOverride: _batchQuantityForDetail(d),
                ),
              );
              await Future<void>.delayed(Duration.zero);
            }
          }
          break;

        case OptimizationMode.orderRange:
          if (_rangeOrderId != null) {
            final details = await _loadDetailsForOrder(_rangeOrderId!);
            final orderName = _getOrderName(_rangeOrderId!);
            final start = math.max(1, _rangeStartItemIndex) - 1;
            final end = _rangeEndItemIndex != null
                ? math.min(details.length, _rangeEndItemIndex!)
                : details.length;

            for (int i = start; i < end; i++) {
              if (i >= 0 && i < details.length) {
                pieces.addAll(
                  _extractPiecesFromDetail(
                    details[i],
                    _rangeOrderId!,
                    orderName,
                    quantityOverride: _batchQuantityForDetail(details[i]),
                  ),
                );
                await Future<void>.delayed(Duration.zero);
              }
            }
          }
          break;

        case OptimizationMode.customElements:
          for (final order in _allOrders) {
            final oId = (order['id'] as num?)?.toInt() ?? 0;
            final details = await _loadDetailsForOrder(oId);
            final orderName = _getOrderName(oId);
            for (final d in details) {
              final dId = (d['id'] as num?)?.toInt() ?? 0;
              if (_selectedDetailIds.contains(dId)) {
                pieces.addAll(
                  _extractPiecesFromDetail(
                    d,
                    oId,
                    orderName,
                    quantityOverride: _batchQuantityForDetail(d),
                  ),
                );
                await Future<void>.delayed(Duration.zero);
              }
            }
          }
          break;
      }

      final barLengthMm = _barLengthMm;
      final sawKerfMm = _sawKerfMm;
      final chuteThresholdMm = _chuteThresholdMm;
      final report = await Isolate.run(
        () => CuttingOptimizerEngine.optimize(
          pieces: pieces,
          barLengthMm: barLengthMm,
          sawKerfMm: sawKerfMm,
          usableRemnantThresholdMm: chuteThresholdMm,
        ),
      );

      if (mounted && generation == _optimizationGeneration) {
        setState(() {
          _report = report;
          _selectedProfileFilter = 'الكل';
          _isOptimizing = false;
        });
        if (report.groups.isNotEmpty) {
          _mobileTabController.animateTo(1);
        }
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              Localization.translate(
                'اكتملت خطة القص في الخلفية وأصبحت جاهزة',
                context.read<AppSettingsProvider>().language,
              ),
            ),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e, st) {
      debugPrint('Optimization error: $e\n$st');
      if (mounted && generation == _optimizationGeneration) {
        setState(() => _isOptimizing = false);
      }
    }
  }

  String _getOrderName(int orderId) {
    final o = _allOrders.firstWhere(
      (order) => order['id'] == orderId,
      orElse: () => {},
    );
    final clientName = o['client_name'] ?? o['name'] ?? '';
    final code = o['order_code'] ?? o['id'] ?? '';
    return 'طلب #$code - $clientName';
  }

  List<CuttingPiece> _extractPiecesFromDetail(
    Map<String, dynamic> detail,
    int orderId,
    String orderName, {
    int? quantityOverride,
  }) {
    final pieces = <CuttingPiece>[];
    final rawJson = detail['partitions_json']?.toString() ?? '';
    if (rawJson.trim().isEmpty) return pieces;

    try {
      final data = jsonDecode(rawJson);
      if (data is! Map) return pieces;

      final window = WindowModel(db: widget.db);
      applyWindowModelFromMap(window, Map<String, dynamic>.from(data));

      final rawQty = detail['quantity'] ?? detail['quantite'] ?? 1;
      final orderedQuantity = (rawQty is num
              ? rawQty.toInt()
              : int.tryParse('$rawQty') ?? 1)
          .clamp(1, 1000);
      final quantity = (quantityOverride ?? orderedQuantity).clamp(
        1,
        orderedQuantity,
      );
      final detailId = (detail['id'] as num?)?.toInt() ?? 0;
      final windowName = detail['window_type'] ?? detail['type'] ?? 'عنصر $detailId';

      final bom = ComponentCalculator.generateBom(window, const {});

      for (final item in bom) {
        if (!item.isActive || item.category != 'profile') continue;
        if (item.pieces == null || item.pieces!.isEmpty) continue;

        final profileName = item.name.trim();
        final profileCode = item.profileCode ?? '';
        final color = (detail['color']?.toString().isNotEmpty == true)
            ? detail['color'].toString()
            : 'Standard';

        for (var pieceIndex = 0; pieceIndex < item.pieces!.length; pieceIndex++) {
          final lenM = item.pieces![pieceIndex];
          final lenMm = (lenM * 1000.0).roundToDouble();
          if (lenMm <= 0) continue;
          final explicitAngles = item.pieceCutAngles != null &&
                  pieceIndex < item.pieceCutAngles!.length
              ? RegExp(r'\d+')
                  .allMatches(item.pieceCutAngles![pieceIndex])
                  .map((match) => int.tryParse(match.group(0) ?? ''))
                  .whereType<int>()
                  .toList()
              : const <int>[];
          final angleLeft = explicitAngles.length >= 2
              ? explicitAngles[0]
              : 45;
          final angleRight = explicitAngles.length >= 2
              ? explicitAngles[1]
              : 45;

          for (int q = 0; q < quantity; q++) {
            pieces.add(
              CuttingPiece(
                id: '${detailId}_${profileName}_${lenMm}_$q',
                orderId: orderId,
                orderName: orderName,
                detailId: detailId,
                windowName: '$windowName (#$quantity)',
                profileName: profileName,
                profileCode: profileCode,
                color: color,
                lengthMm: lenMm,
                angleLeft: angleLeft,
                angleRight: angleRight,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint('Error parsing detail for cutting: $e');
    }
    return pieces;
  }

  int _batchQuantityForDetail(Map<String, dynamic> detail) {
    final detailId = (detail['id'] as num?)?.toInt() ?? 0;
    final raw = detail['quantity'] ?? detail['quantite'] ?? 1;
    final ordered = (raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1)
        .clamp(1, 1000);
    return (_detailBatchQuantities[detailId] ?? ordered).clamp(1, ordered);
  }

  Future<void> _exportPdfReport() async {
    if (_report == null || _report!.groups.isEmpty) return;

    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(Localization.translate('جاري تجهيز وثيقة تحسين القص PDF...', lang), style: const TextStyle(fontFamily: 'Cairo')),
      ),
    );

    try {
      final pdf = pw.Document();
      final fonts = await PdfFontCache.load();
      final ttf = fonts.regular;
      final ttfBold = fonts.bold;

      pdf.addPage(
        pw.MultiPage(
          pageFormat: PdfPageFormat.a4.landscape,
          theme: pw.ThemeData.withFont(base: ttf, bold: ttfBold),
          textDirection: lang == AppLanguage.arabic ? pw.TextDirection.rtl : pw.TextDirection.ltr,
          build: (ctx) => [
            // Title Header
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    Localization.translate('مخطط تحسين القص (Optimisation de Coupe)', lang),
                    style: pw.TextStyle(font: ttfBold, fontSize: 18),
                  ),
                  pw.Text(
                    '${Localization.translate('التاريخ:', lang)} ${DateFormat('yyyy-MM-dd HH:mm').format(DateTime.now())}',
                    style: pw.TextStyle(font: ttf, fontSize: 10),
                  ),
                ],
              ),
            ),
            pw.SizedBox(height: 8),

            // Summary Stats
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400),
                borderRadius: pw.BorderRadius.circular(6),
              ),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceAround,
                children: [
                  pw.Text('${Localization.translate('إجمالي البارات المطلوبة', lang)}: ${_report!.totalBars}', style: pw.TextStyle(font: ttfBold, fontSize: 11)),
                  pw.Text('${Localization.translate('إجمالي القطع:', lang)} ${_report!.totalPieces}', style: pw.TextStyle(font: ttf, fontSize: 11)),
                  pw.Text('${Localization.translate('نسبة الاستغلال والوفر:', lang)} ${_report!.overallEfficiency.toStringAsFixed(1)}%', style: pw.TextStyle(font: ttfBold, fontSize: 11, color: PdfColors.blue800)),
                  pw.Text('${Localization.translate('الفواضل الصالحة للاستعمال:', lang)} ${_report!.totalMetersUsableRemnants.toStringAsFixed(2)} ${Localization.translate('م', lang)}', style: pw.TextStyle(font: ttf, fontSize: 11, color: PdfColors.green800)),
                ],
              ),
            ),
            pw.SizedBox(height: 12),

            // Tables per Profile Group
            ..._report!.groups.map((group) {
              return pw.Column(
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Container(
                    color: PdfColors.grey200,
                    padding: const pw.EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    child: pw.Row(
                      mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                      children: [
                        pw.Text('${group.profileName} (${group.color})', style: pw.TextStyle(font: ttfBold, fontSize: 12)),
                        pw.Text('${Localization.translate('البارات:', lang)} ${group.barsNeeded} | ${Localization.translate('القطع:', lang)} ${group.totalPieces} | ${Localization.translate('الكفاءة:', lang)} ${group.efficiencyPercentage.toStringAsFixed(1)}%', style: pw.TextStyle(font: ttf, fontSize: 10)),
                      ],
                    ),
                  ),
                  pw.SizedBox(height: 4),
                  pw.TableHelper.fromTextArray(
                    border: pw.TableBorder.all(color: PdfColors.grey300),
                    headerStyle: pw.TextStyle(font: ttfBold, fontSize: 9),
                    cellStyle: pw.TextStyle(font: ttf, fontSize: 8),
                    headers: [
                      Localization.translate('البار #', lang),
                      Localization.translate('القطع المقصوصة (مم)', lang),
                      Localization.translate('المستغل (مم)', lang),
                      Localization.translate('الفضل المتبقي (مم)', lang),
                      Localization.translate('الحالة', lang),
                    ],
                    data: group.bars.map((bar) {
                      final cutsDesc = bar.cuts.map((c) => '${c.piece.lengthMm.toStringAsFixed(0)} ${Localization.translate('مم', lang)} (${c.piece.windowName})').join(' + ');
                      return [
                        '${Localization.translate('بار', lang)} ${bar.barNumber}',
                        cutsDesc,
                        '${bar.usedLengthMm.toStringAsFixed(0)} ${Localization.translate('مم', lang)}',
                        '${bar.remnantLengthMm.toStringAsFixed(0)} ${Localization.translate('مم', lang)}',
                        bar.isUsableRemnant ? Localization.translate('فضلة صالحة', lang) : Localization.translate('رايش', lang),
                      ];
                    }).toList(),
                  ),
                  pw.SizedBox(height: 12),
                ],
              );
            }),
          ],
        ),
      );

      await Printing.layoutPdf(
        onLayout: (format) async => pdf.save(),
        name: 'cutting_optimization_${DateFormat('yyyyMMdd_HHmm').format(DateTime.now())}.pdf',
      );
    } catch (e) {
      debugPrint('Error generating cutting optimization PDF: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final lang = Provider.of<AppSettingsProvider>(context).language;
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final primaryColor = Theme.of(context).primaryColor;
    final screenWidth = MediaQuery.sizeOf(context).width;
    final isMobile = screenWidth < 850;

    return Scaffold(
      backgroundColor: isDark ? const Color(0xFF0F172A) : const Color(0xFFF8FAFC),
      appBar: AppBar(
        title: Text(
          isMobile
              ? Localization.translate('تحسين القص (Optimisation de Coupe)', lang)
              : Localization.translate('تحسين وتقطيع البروفيلات (Optimisation)', lang),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontWeight: FontWeight.bold,
            fontSize: isMobile ? 14 : 18,
          ),
        ),
        centerTitle: true,
        bottom: isMobile
            ? TabBar(
                controller: _mobileTabController,
                indicatorColor: Colors.white,
                indicatorWeight: 3,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                labelStyle: const TextStyle(
                  fontFamily: 'Cairo',
                  fontWeight: FontWeight.bold,
                  fontSize: 12.5,
                ),
                tabs: [
                  Tab(
                    icon: const Icon(Icons.tune_rounded, size: 18),
                    text: Localization.translate('الإعدادات', lang),
                  ),
                  Tab(
                    icon: const Icon(Icons.analytics_rounded, size: 18),
                    text: _report != null && _report!.groups.isNotEmpty
                        ? '${Localization.translate('النتائج', lang)} (${_report!.totalBars})'
                        : Localization.translate('النتائج', lang),
                  ),
                ],
              )
            : null,
        actions: [
          if (_report != null && _report!.groups.isNotEmpty) ...[
            IconButton(
              icon: const Icon(Icons.picture_as_pdf_rounded),
              tooltip: Localization.translate('طباعة وحفظ كـ PDF', lang),
              onPressed: _exportPdfReport,
            ),
            IconButton(
              icon: const Icon(Icons.qr_code_2_rounded),
              tooltip: Localization.translate('طباعة ملصقات الباركود للقطع', lang),
              onPressed: () {
                final targetOrderId = _selectedOrderId ?? widget.initialOrderId;
                if (targetOrderId == null) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text(
                        lang == AppLanguage.french
                            ? 'Veuillez sélectionner une commande spécifique pour imprimer ses étiquettes'
                            : 'يرجى اختيار طلبية محددة لطباعة ملصقات الباركود الخاصة بها',
                      ),
                    ),
                  );
                  return;
                }
                final matchedOrder = _allOrders.firstWhere(
                  (o) => o['id'] == targetOrderId,
                  orElse: () => {'id': targetOrderId},
                );
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => OrderMeasurementsConfirmScreen(
                      orderData: matchedOrder,
                      db: widget.db,
                    ),
                  ),
                );
              },
            ),
          ],
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: Localization.translate('إعادة الحساب والتحسين', lang),
            onPressed: _runOptimization,
          ),
        ],
      ),
      body: _isLoadingOrders
          ? const Center(child: CircularProgressIndicator())
          : isMobile
              ? TabBarView(
                  controller: _mobileTabController,
                  children: [
                    // تبويب الإعدادات واختيار الطلبيات على الهاتف
                    SingleChildScrollView(
                      padding: const EdgeInsets.all(14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          _buildModeSelector(lang, isDark),
                          const SizedBox(height: 12),
                          _buildScopeSelectorCard(lang, isDark),
                          const SizedBox(height: 14),
                          _buildCuttingParamsCard(lang, isDark),
                          const SizedBox(height: 16),
                          ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: primaryColor,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                            onPressed: _isOptimizing ? null : _runOptimization,
                            icon: _isOptimizing
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      valueColor: AlwaysStoppedAnimation(Colors.white),
                                    ),
                                  )
                                : const Icon(Icons.play_arrow_rounded),
                            label: Text(
                              Localization.translate('تشغيل خوارزمية التحسين', lang),
                              style: const TextStyle(
                                fontFamily: 'Cairo',
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),

                    // تبويب نتائج ومخططات التقطيع على الهاتف
                    _isOptimizing
                        ? const Center(child: CircularProgressIndicator())
                        : (_report == null || _report!.groups.isEmpty)
                            ? _buildEmptyState(lang, isDark)
                            : _buildResultsDashboard(lang, isDark),
                  ],
                )
              : Column(
                  children: [
                    // Mode Selector Bar (4 Modes)
                    _buildModeSelector(lang, isDark),

                    // Main Content Area (شاشات الكمبيوتر والتابلت الواسعة)
                    Expanded(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Left Configuration Sidebar
                          SizedBox(
                            width: 320,
                            child: SingleChildScrollView(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  _buildScopeSelectorCard(lang, isDark),
                                  const SizedBox(height: 16),
                                  _buildCuttingParamsCard(lang, isDark),
                                  const SizedBox(height: 16),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: primaryColor,
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(vertical: 14),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                    ),
                                    onPressed: _isOptimizing ? null : _runOptimization,
                                    icon: _isOptimizing
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              valueColor: AlwaysStoppedAnimation(Colors.white),
                                            ),
                                          )
                                        : const Icon(Icons.play_arrow_rounded),
                                    label: Text(
                                      Localization.translate('تشغيل خوارزمية التحسين', lang),
                                      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),

                          // Right Results Area
                          Expanded(
                            child: _isOptimizing
                                ? const Center(child: CircularProgressIndicator())
                                : (_report == null || _report!.groups.isEmpty)
                                    ? _buildEmptyState(lang, isDark)
                                    : _buildResultsDashboard(lang, isDark),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
    );
  }

  Widget _buildModeSelector(AppLanguage lang, bool isDark) {
    return Container(
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildModeTab(
              mode: OptimizationMode.singleOrder,
              title: Localization.translate('1. طلبية كاملة', lang),
              icon: Icons.assignment_rounded,
            ),
            const SizedBox(width: 8),
            _buildModeTab(
              mode: OptimizationMode.multipleOrders,
              title: Localization.translate('2. عدة طلبيات مجمعة', lang),
              icon: Icons.layers_rounded,
            ),
            const SizedBox(width: 8),
            _buildModeTab(
              mode: OptimizationMode.orderRange,
              title: Localization.translate('3. جزء من طلبية لنهايتها', lang),
              icon: Icons.start_rounded,
            ),
            const SizedBox(width: 8),
            _buildModeTab(
              mode: OptimizationMode.customElements,
              title: Localization.translate('4. عناصر مختارة من طلبيات', lang),
              icon: Icons.check_box_rounded,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildModeTab({
    required OptimizationMode mode,
    required String title,
    required IconData icon,
  }) {
    final isSelected = _selectedMode == mode;
    final primaryColor = Theme.of(context).primaryColor;

    return ChoiceChip(
      selected: isSelected,
      onSelected: (selected) {
        if (selected) {
          setState(() => _selectedMode = mode);
          _runOptimization();
        }
      },
      avatar: Icon(icon, size: 16, color: isSelected ? Colors.white : primaryColor),
      label: Text(
        title,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
          fontSize: 12,
          color: isSelected ? Colors.white : null,
        ),
      ),
      selectedColor: primaryColor,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    );
  }

  Widget _buildScopeSelectorCard(AppLanguage lang, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localization.translate('نطاق التحسين', lang),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            if (_selectedMode == OptimizationMode.singleOrder) ...[
              DropdownButtonFormField<int>(
                value: _selectedOrderId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: Localization.translate('اختر الطلبية', lang),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: _allOrders.map((o) {
                  final id = (o['id'] as num?)?.toInt() ?? 0;
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(
                      _getOrderName(id),
                      style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
                      overflow: TextOverflow.ellipsis,
                    ),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _selectedOrderId = val);
                  if (val != null) _loadDetailsForOrder(val);
                },
              ),
              if (_selectedOrderId != null) ...[
                const SizedBox(height: 10),
                FutureBuilder<List<Map<String, dynamic>>>(
                  future: _loadDetailsForOrder(_selectedOrderId!),
                  builder: (context, snapshot) {
                    final details = snapshot.data ?? const [];
                    if (details.isEmpty) return const SizedBox.shrink();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          Localization.translate(
                            'كمية دفعة القص الحالية لكل عنصر',
                            lang,
                          ),
                          style: const TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const SizedBox(height: 6),
                        for (final detail in details)
                          _buildDetailBatchQuantityField(detail, lang),
                      ],
                    );
                  },
                ),
              ],
            ] else if (_selectedMode == OptimizationMode.multipleOrders) ...[
              Text(
                '${Localization.translate('حدد الطلبيات المراد دمجها', lang)} (${_selectedOrderIds.length}):',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                height: 180,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _allOrders.length,
                  itemBuilder: (context, idx) {
                    final o = _allOrders[idx];
                    final id = (o['id'] as num?)?.toInt() ?? 0;
                    final isChecked = _selectedOrderIds.contains(id);
                    return CheckboxListTile(
                      dense: true,
                      value: isChecked,
                      title: Text(_getOrderName(id), style: const TextStyle(fontFamily: 'Cairo', fontSize: 11)),
                      onChanged: (checked) {
                        setState(() {
                          if (checked == true) {
                            _selectedOrderIds.add(id);
                            _loadDetailsForOrder(id);
                          } else {
                            _selectedOrderIds.remove(id);
                          }
                        });
                      },
                    );
                  },
                ),
              ),
            ] else if (_selectedMode == OptimizationMode.orderRange) ...[
              DropdownButtonFormField<int>(
                value: _rangeOrderId,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: Localization.translate('الطلبية المحددة', lang),
                  border: const OutlineInputBorder(),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                ),
                items: _allOrders.map((o) {
                  final id = (o['id'] as num?)?.toInt() ?? 0;
                  return DropdownMenuItem<int>(
                    value: id,
                    child: Text(_getOrderName(id), style: const TextStyle(fontFamily: 'Cairo', fontSize: 12)),
                  );
                }).toList(),
                onChanged: (val) {
                  setState(() => _rangeOrderId = val);
                  if (val != null) _loadDetailsForOrder(val);
                },
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextFormField(
                      initialValue: '$_rangeStartItemIndex',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: Localization.translate('من العنصر رقم', lang),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) => _rangeStartItemIndex = int.tryParse(val) ?? 1,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextFormField(
                      initialValue: _rangeEndItemIndex != null ? '$_rangeEndItemIndex' : '',
                      keyboardType: TextInputType.number,
                      decoration: InputDecoration(
                        labelText: Localization.translate('إلى نهاية الطلب', lang),
                        hintText: Localization.translate('النهاية', lang),
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (val) => _rangeEndItemIndex = int.tryParse(val),
                    ),
                  ),
                ],
              ),
            ] else if (_selectedMode == OptimizationMode.customElements) ...[
              Text(
                '${Localization.translate('اختر العناصر المطلوبة', lang)} (${_selectedDetailIds.length}):',
                style: const TextStyle(fontFamily: 'Cairo', fontSize: 12),
              ),
              const SizedBox(height: 8),
              Container(
                height: 220,
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.grey.withOpacity(0.3)),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: ListView.builder(
                  itemCount: _allOrders.length,
                  itemBuilder: (context, idx) {
                    final o = _allOrders[idx];
                    final id = (o['id'] as num?)?.toInt() ?? 0;
                    return FutureBuilder<List<Map<String, dynamic>>>(
                      future: _loadDetailsForOrder(id),
                      builder: (context, snap) {
                        final items = snap.data ?? [];
                        if (items.isEmpty) return const SizedBox.shrink();
                        return AutoScrollExpansionTile(
                          dense: true,
                          title: Text(_getOrderName(id), style: const TextStyle(fontFamily: 'Cairo', fontSize: 11, fontWeight: FontWeight.bold)),
                          children: items.map((d) {
                            final dId = (d['id'] as num?)?.toInt() ?? 0;
                            final wName = d['window_type'] ?? '${Localization.translate('إطار', lang)} #$dId';
                            final rawQty = d['quantity'] ?? d['quantite'] ?? 1;
                            final qty = (rawQty is num
                                    ? rawQty.toInt()
                                    : int.tryParse('$rawQty') ?? 1)
                                .clamp(1, 1000);
                            final isChecked = _selectedDetailIds.contains(dId);
                            return CheckboxListTile(
                              dense: true,
                              value: isChecked,
                              title: Text(
                                wName,
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 10,
                                ),
                              ),
                              subtitle: Text(
                                '${Localization.translate('المطلوب', lang)}: $qty  •  '
                                '${Localization.translate('دفعة القص', lang)}: '
                                '${_detailBatchQuantities[dId] ?? qty}',
                                style: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 9,
                                ),
                              ),
                              secondary: SizedBox(
                                width: 58,
                                child: TextFormField(
                                  key: ValueKey(
                                    'cut-batch-$dId',
                                  ),
                                  initialValue:
                                      '${_detailBatchQuantities[dId] ?? qty}',
                                  enabled: isChecked,
                                  keyboardType: TextInputType.number,
                                  textAlign: TextAlign.center,
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (value) {
                                    final parsed = int.tryParse(value);
                                    if (parsed == null) return;
                                    _detailBatchQuantities[dId] = parsed.clamp(
                                      1,
                                      qty,
                                    );
                                  },
                                ),
                              ),
                              onChanged: (c) {
                                setState(() {
                                  if (c == true) {
                                    _selectedDetailIds.add(dId);
                                    _detailBatchQuantities.putIfAbsent(
                                      dId,
                                      () => qty,
                                    );
                                  } else {
                                    _selectedDetailIds.remove(dId);
                                  }
                                });
                              },
                            );
                          }).toList(),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailBatchQuantityField(
    Map<String, dynamic> detail,
    AppLanguage lang,
  ) {
    final detailId = (detail['id'] as num?)?.toInt() ?? 0;
    final raw = detail['quantity'] ?? detail['quantite'] ?? 1;
    final ordered = (raw is num ? raw.toInt() : int.tryParse('$raw') ?? 1)
        .clamp(1, 1000);
    final name = detail['window_type'] ?? detail['type'] ?? 'عنصر $detailId';
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$name (${Localization.translate('المطلوب', lang)}: $ordered)',
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 10),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 62,
            child: TextFormField(
              key: ValueKey('single-cut-batch-$detailId'),
              initialValue: '${_detailBatchQuantities[detailId] ?? ordered}',
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration: const InputDecoration(
                isDense: true,
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                final parsed = int.tryParse(value);
                if (parsed != null) {
                  _detailBatchQuantities[detailId] = parsed.clamp(1, ordered);
                }
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCuttingParamsCard(AppLanguage lang, bool isDark) {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              Localization.translate('إعدادات المنشار والبارات', lang),
              style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<double>(
              value: _barLengthMm,
              decoration: InputDecoration(
                labelText: Localization.translate('طول البار الخام القياسي', lang),
                border: const OutlineInputBorder(),
                contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              ),
              items: [
                DropdownMenuItem(value: 6000.0, child: Text('6.00 ${Localization.translate('متر', lang)} (6000 ${Localization.translate('مم', lang)})')),
                DropdownMenuItem(value: 6500.0, child: Text('6.50 ${Localization.translate('متر', lang)} (6500 ${Localization.translate('مم', lang)})')),
                DropdownMenuItem(value: 5800.0, child: Text('5.80 ${Localization.translate('متر', lang)} (5800 ${Localization.translate('مم', lang)})')),
              ],
              onChanged: (val) {
                if (val != null) setState(() => _barLengthMm = val);
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    initialValue: '$_sawKerfMm',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: Localization.translate('سماكة القرص (Kerf)', lang),
                      suffixText: Localization.translate('مم', lang),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      final v = double.tryParse(val);
                      if (v != null && v > 0) _sawKerfMm = v;
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextFormField(
                    initialValue: '$_chuteThresholdMm',
                    keyboardType: const TextInputType.numberWithOptions(decimal: true),
                    decoration: InputDecoration(
                      labelText: Localization.translate('حد الفضلة الصالحة', lang),
                      suffixText: Localization.translate('مم', lang),
                      border: const OutlineInputBorder(),
                    ),
                    onChanged: (val) {
                      final v = double.tryParse(val);
                      if (v != null && v > 0) _chuteThresholdMm = v;
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(AppLanguage lang, bool isDark) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.content_cut_rounded, size: 64, color: Colors.grey.withOpacity(0.4)),
            const SizedBox(height: 12),
            Text(
              Localization.translate('اضغط على "تشغيل خوارزمية التحسين" لبدء القص الأمثل', lang),
              textAlign: TextAlign.center,
              style: const TextStyle(fontFamily: 'Cairo', fontSize: 15, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultsDashboard(AppLanguage lang, bool isDark) {
    final report = _report!;
    final filteredGroups = _selectedProfileFilter == 'الكل'
        ? report.groups
        : report.groups.where((g) => g.profileName == _selectedProfileFilter).toList();

    return SingleChildScrollView(
      padding: EdgeInsets.all(MediaQuery.sizeOf(context).width < 650 ? 10 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Stat Badges
          Builder(
            builder: (context) {
              final isCompact = MediaQuery.sizeOf(context).width < 650;
              final cardBars = _buildMetricCard(
                title: Localization.translate('إجمالي البارات', lang),
                value: '${report.totalBars} ${Localization.translate('بار', lang)}',
                subtitle: '${Localization.translate('طول', lang)} ${_barLengthMm.toInt()} ${Localization.translate('مم', lang)}',
                color: const Color(0xFF2563EB),
                icon: Icons.view_column_rounded,
                isDark: isDark,
              );
              final cardPieces = _buildMetricCard(
                title: Localization.translate('عدد القطع المطلوبة', lang),
                value: '${report.totalPieces} ${Localization.translate('قطعة', lang)}',
                subtitle: '${report.totalMetersUsed.toStringAsFixed(1)} ${Localization.translate('متر طولي', lang)}',
                color: const Color(0xFF0D9488),
                icon: Icons.straighten_rounded,
                isDark: isDark,
              );
              final cardEfficiency = _buildMetricCard(
                title: Localization.translate('نسبة الوفر والكفاءة', lang),
                value: '${report.overallEfficiency.toStringAsFixed(1)}%',
                subtitle: Localization.translate('استغلال أمثل', lang),
                color: const Color(0xFF10B981),
                icon: Icons.trending_up_rounded,
                isDark: isDark,
              );
              final cardRemnants = _buildMetricCard(
                title: '${Localization.translate('الفواضل الصالحة', lang)} (≥${_chuteThresholdMm.toInt()}${Localization.translate('مم', lang)})',
                value: '${report.totalMetersUsableRemnants.toStringAsFixed(1)} ${Localization.translate('م', lang)}',
                subtitle: Localization.translate('تُحفظ لإعادة الاستخدام', lang),
                color: const Color(0xFFF59E0B),
                icon: Icons.inventory_2_rounded,
                isDark: isDark,
              );

              if (isCompact) {
                return Column(
                  children: [
                    Row(
                      children: [
                        Expanded(child: cardBars),
                        const SizedBox(width: 8),
                        Expanded(child: cardPieces),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(child: cardEfficiency),
                        const SizedBox(width: 8),
                        Expanded(child: cardRemnants),
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: cardBars),
                  const SizedBox(width: 10),
                  Expanded(child: cardPieces),
                  const SizedBox(width: 10),
                  Expanded(child: cardEfficiency),
                  const SizedBox(width: 10),
                  Expanded(child: cardRemnants),
                ],
              );
            },
          ),
          const SizedBox(height: 16),

          // Profile Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                ChoiceChip(
                  label: Text(Localization.translate('الكل', lang), style: const TextStyle(fontFamily: 'Cairo')),
                  selected: _selectedProfileFilter == 'الكل',
                  onSelected: (s) => setState(() => _selectedProfileFilter = 'الكل'),
                ),
                const SizedBox(width: 8),
                ...report.groups.map((g) {
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ChoiceChip(
                      label: Text('${g.profileName} (${g.barsNeeded} ${Localization.translate('بار', lang)})', style: const TextStyle(fontFamily: 'Cairo')),
                      selected: _selectedProfileFilter == g.profileName,
                      onSelected: (s) => setState(() => _selectedProfileFilter = g.profileName),
                    ),
                  );
                }),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Visual Bars per Group
          ...filteredGroups.map((group) => _buildGroupCard(group, lang, isDark)),
        ],
      ),
    );
  }

  Widget _buildGroupCard(ProfileOptimizationGroup group, AppLanguage lang, bool isDark) {
    final isMobile = MediaQuery.sizeOf(context).width < 650;
    final groupTitle = Row(
      children: [
        Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: const Color(0xFF2563EB).withOpacity(0.12),
            borderRadius: BorderRadius.circular(8),
          ),
          child: const Icon(Icons.architecture_rounded, color: Color(0xFF2563EB), size: 20),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${group.profileName} - ${Localization.translate('لون', lang)} (${group.color})',
            maxLines: isMobile ? 2 : 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.bold,
              fontSize: isMobile ? 13 : 16,
            ),
          ),
        ),
      ],
    );
    final efficiencyChip = Chip(
      backgroundColor: const Color(0xFF10B981).withOpacity(0.15),
      label: Text(
        '${Localization.translate('كفاءة', lang)}: ${group.efficiencyPercentage.toStringAsFixed(1)}% | ${group.barsNeeded} ${Localization.translate('بار', lang)}',
        style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, color: Color(0xFF059669), fontSize: 12),
      ),
    );
    return Card(
      margin: const EdgeInsets.only(bottom: 20),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: isDark ? const Color(0xFF1E293B) : Colors.white,
      elevation: 2,
      child: Padding(
        padding: EdgeInsets.all(isMobile ? 12 : 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isMobile) ...[
              groupTitle,
              const SizedBox(height: 8),
              Align(alignment: AlignmentDirectional.centerStart, child: efficiencyChip),
            ] else
              Row(
                children: [
                  Expanded(child: groupTitle),
                  const SizedBox(width: 12),
                  efficiencyChip,
                ],
              ),
            const SizedBox(height: 14),

            // Bar Layouts
            ...group.bars.map((bar) => _buildBarLayoutView(bar, lang, isDark)),
          ],
        ),
      ),
    );
  }

  Widget _buildBarLayoutView(OptimizedBar bar, AppLanguage lang, bool isDark) {
    final isMobile = MediaQuery.sizeOf(context).width < 650;
    final barTitle = Text(
      '${Localization.translate('بار رقم', lang)} #${bar.barNumber} (${bar.barLengthMm.toInt()} ${Localization.translate('مم', lang)})',
      style: const TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.bold, fontSize: 13),
    );
    final remnantText = Text(
      bar.isUsableRemnant
          ? '${Localization.translate('فضل متبقي صالح:', lang)} ${bar.remnantLengthMm.toInt()} ${Localization.translate('مم', lang)}'
          : '${Localization.translate('رايش هدر:', lang)} ${bar.remnantLengthMm.toInt()} ${Localization.translate('مم', lang)}',
      style: TextStyle(
        fontFamily: 'Cairo',
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: bar.isUsableRemnant ? const Color(0xFF059669) : Colors.red,
      ),
    );
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF0F172A) : const Color(0xFFF1F5F9),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (isMobile) ...[
            barTitle,
            const SizedBox(height: 2),
            remnantText,
          ] else
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [barTitle, remnantText],
            ),
          const SizedBox(height: 8),

          // Visual Bar Graphic
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: SizedBox(
              height: 38,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final totalWidth = constraints.maxWidth;
                  return Row(
                    children: [
                      ...bar.cuts.map((cut) {
                        final cutPct = (cut.lengthMm / bar.barLengthMm).clamp(0.01, 1.0);
                        return Container(
                          width: math.max(1.0, (totalWidth * cutPct) - 1.5),
                          margin: const EdgeInsets.only(right: 1.5),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2563EB),
                            border: Border.all(color: Colors.white, width: 0.5),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '${cut.lengthMm.toInt()} ${Localization.translate('مم', lang)}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        );
                      }),
                      if (bar.remnantLengthMm > 0)
                        Expanded(
                          child: Container(
                            decoration: BoxDecoration(
                              color: bar.isUsableRemnant
                                  ? const Color(0xFF10B981) // Green for usable chute
                                  : const Color(0xFF94A3B8), // Grey for scrap
                              border: Border.all(color: Colors.white, width: 0.5),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              bar.isUsableRemnant
                                  ? '${Localization.translate('فضلة', lang)} ${bar.remnantLengthMm.toInt()}'
                                  : '${Localization.translate('رايش', lang)} ${bar.remnantLengthMm.toInt()}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 9,
                                fontWeight: FontWeight.bold,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          const SizedBox(height: 6),

          // Pieces breakdown description text
          Wrap(
            spacing: 8,
            children: bar.cuts.map((c) {
              return Text(
                '• ${c.lengthMm.toInt()}${Localization.translate('مم', lang)} (${c.piece.windowName})',
                style: TextStyle(
                  fontFamily: 'Cairo',
                  fontSize: 11,
                  color: isDark ? Colors.grey[300] : Colors.grey[700],
                ),
              );
            }).toList(),
          ),
        ],
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required String subtitle,
    required Color color,
    required IconData icon,
    required bool isDark,
  }) {
    return Container(
      constraints: const BoxConstraints(minHeight: 104),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF1E293B) : Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(isDark ? 0.2 : 0.04),
            blurRadius: 8,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: isDark ? Colors.grey[400] : Colors.grey[600],
                  ),
                ),
              ),
              const SizedBox(width: 4),
              Icon(icon, size: 16, color: color),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 18, fontWeight: FontWeight.bold, color: color),
          ),
          Text(
            subtitle,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 10, color: isDark ? Colors.grey[500] : Colors.grey[400]),
          ),
        ],
      ),
    );
  }
}
