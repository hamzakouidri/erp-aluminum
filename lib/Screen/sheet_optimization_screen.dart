import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/sheet_cutting_optimizer_engine.dart';
import '../settings/app_settings.dart';
import '../sql_database.dart';

class SheetOptimizationScreen extends StatefulWidget {
  final int orderId;
  final String orderName;
  final List<SheetDemandPiece>? demandPieces;

  const SheetOptimizationScreen({
    super.key,
    required this.orderId,
    this.orderName = '',
    this.demandPieces,
  });

  @override
  State<SheetOptimizationScreen> createState() => _SheetOptimizationScreenState();
}

class _SheetOptimizationScreenState extends State<SheetOptimizationScreen> {
  final SqlDatabase _db = SqlDatabase();
  bool _loading = true;
  bool _includeGlass = false;
  SheetOptimizationFullReport? _report;
  double _sawKerfMm = SheetCuttingOptimizerEngine.defaultSawKerfMm;

  @override
  void initState() {
    super.initState();
    _runOptimization();
  }

  Future<void> _runOptimization() async {
    setState(() => _loading = true);
    final standards = await _db.readStandardSheets();
    final remnants = await _db.readAvailableSheetRemnants();

    List<SheetDemandPiece> pieces =
        widget.demandPieces != null && widget.demandPieces!.isNotEmpty && !_includeGlass
            ? List<SheetDemandPiece>.from(widget.demandPieces!)
            : [];

    if ((pieces.isEmpty || _includeGlass) && widget.orderId > 0) {
      final details = await _db.readCommandeDetails(widget.orderId);
      pieces = SheetCuttingOptimizerEngine.extractPiecesFromOrderDetails(
        orderDetails: details,
        db: _db,
        includeGlass: _includeGlass,
      );
    }

    final report = SheetCuttingOptimizerEngine.optimize(
      demandPieces: pieces,
      availableStandardSheets: standards,
      availableRemnants: remnants,
      sawKerfMm: _sawKerfMm,
    );

    if (mounted) {
      setState(() {
        _report = report;
        _loading = false;
      });
    }
  }

  Future<void> _saveGeneratedRemnantsToInventory(OptimizedSheet sheet) async {
    final lang = Provider.of<AppSettingsProvider>(context, listen: false).language;
    final isArabic = lang == AppLanguage.arabic;

    if (sheet.usableRemnants.isEmpty) return;

    final myDb = await _db.db;
    if (myDb == null) return;

    final now = DateTime.now().toIso8601String();
    var count = 0;

    for (final rem in sheet.usableRemnants) {
      final ticket = 'RM-${DateTime.now().millisecondsSinceEpoch % 100000 + count}';
      await myDb.insert('MaterialRemnants', {
        'ticket_code': ticket,
        'item_id': 0,
        'item_type': sheet.materialType,
        'material_type': sheet.materialType,
        'length_mm': rem.length,
        'width_mm': rem.width,
        'allow_rotation': 1,
        'location_id': 1,
        'source_order_id': widget.orderId,
        'status': 'available',
        'note': 'فضلة ناتجة من طلبية ${widget.orderName} (${sheet.sheetName})',
        'created_at': now,
        'updated_at': now,
      });
      count++;
    }

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            isArabic
                ? 'تم حفظ $count فضلة بنجاح في مخزون الفضلات ✅'
                : '$count chute(s) enregistrée(s) au stock avec succès ✅',
          ),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = Provider.of<AppSettingsProvider>(context);
    final lang = settings.language;
    final isArabic = lang == AppLanguage.arabic;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          isArabic ? 'تقطيع وتوزيع الألواح والصفائح (2D)' : 'Optimisation de débit 2D (Panneaux)',
          style: TextStyle(
            fontFamily: isArabic ? 'Cairo' : null,
            fontWeight: FontWeight.bold,
          ),
        ),
        actions: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                isArabic ? 'تضمين الزجاج' : 'Inclure verre',
                style: TextStyle(
                  fontSize: 12,
                  fontFamily: isArabic ? 'Cairo' : null,
                  fontWeight: FontWeight.w600,
                ),
              ),
              Switch(
                value: _includeGlass,
                activeThumbColor: Colors.tealAccent,
                onChanged: (val) {
                  setState(() => _includeGlass = val);
                  _runOptimization();
                },
              ),
            ],
          ),
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: isArabic ? 'إعادة الحساب' : 'Recalculer',
            onPressed: _runOptimization,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _report == null || _report!.groups.isEmpty
              ? Center(
                  child: Text(
                    isArabic ? 'لا توجد قطع ألواح للتقطيع في هذه الطلبية' : 'Aucune pièce de panneau à débiter',
                    style: TextStyle(fontFamily: isArabic ? 'Cairo' : null),
                  ),
                )
              : ListView(
                  padding: const EdgeInsets.all(14),
                  children: [
                    // بطاقة الإحصائيات العامة للطلبية
                    _buildOverviewCard(lang, isArabic),
                    const SizedBox(height: 14),

                    // عرض كل مجموعة (مادة ولون)
                    ..._report!.groups.entries.map((entry) {
                      final group = entry.value;
                      return _buildGroupSection(group, lang, isArabic);
                    }),
                  ],
                ),
    );
  }

  Widget _buildOverviewCard(AppLanguage lang, bool isArabic) {
    final rep = _report!;
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.dashboard_customize_outlined, color: Colors.blueAccent),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'ملخص استهلاك الألواح والفضلات' : 'Résumé global du débit des panneaux',
                  style: TextStyle(
                    fontFamily: isArabic ? 'Cairo' : null,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _buildMetricTile(
                    label: isArabic ? 'ألواح جديدة مطلوبة' : 'Plaques neuves',
                    value: '${rep.totalNewSheets}',
                    icon: Icons.layers,
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: isArabic ? 'فضلات مسترجعة' : 'Chutes réutilisées',
                    value: '${rep.totalRemnantsUsed}',
                    icon: Icons.recycling,
                    color: Colors.teal,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _buildMetricTile(
                    label: isArabic ? 'فضلات جديدة ناتجة' : 'Nouvelles chutes',
                    value: '${rep.totalNewRemnants}',
                    icon: Icons.add_to_photos,
                    color: Colors.orange,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMetricTile({
    required String label,
    required String value,
    required IconData icon,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupSection(
    SheetOptimizationGroupReport group,
    AppLanguage lang,
    bool isArabic,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 22,
                decoration: BoxDecoration(
                  color: Colors.teal,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${group.materialType.toUpperCase()} ${group.color.isNotEmpty ? '· ${group.color}' : ''}',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
              const Spacer(),
              Text(
                '${isArabic ? 'كفاءة الاستغلال:' : 'Rendement:'} ${group.overallEfficiencyPercentage.toStringAsFixed(1)}%',
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.teal,
                  fontSize: 13,
                ),
              ),
            ],
          ),
        ),

        // قائمة الألواح في هذه المجموعة
        ...group.sheets.map((sheet) => _buildSheetCard(sheet, lang, isArabic)),
        const SizedBox(height: 16),
      ],
    );
  }

  Widget _buildSheetCard(OptimizedSheet sheet, AppLanguage lang, bool isArabic) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.symmetric(vertical: 8),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ترويسة اللوح
            Row(
              children: [
                Icon(
                  sheet.isFromRemnant ? Icons.recycling : Icons.crop_portrait,
                  color: sheet.isFromRemnant ? Colors.teal : Colors.blueAccent,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    sheet.sheetName,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.teal.shade50,
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.teal.shade200),
                  ),
                  child: Text(
                    '${isArabic ? 'استغلال:' : 'Rendement:'} ${sheet.efficiencyPercentage.toStringAsFixed(1)}%',
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: Colors.teal.shade800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${isArabic ? 'أبعاد اللوح:' : 'Format:'} ${sheet.sheetLengthMm.round()} × ${sheet.sheetWidthMm.round()} مم (${sheet.totalSheetAreaSqm.toStringAsFixed(2)} m²)',
              style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
            ),
            const SizedBox(height: 12),

            // رسم بصري للوح ثنائي الأبعاد (2D Visual Canvas)
            _buildVisualSheetCanvas(sheet),
            const SizedBox(height: 12),

            // الفضلات الجديدة الناتجة وزر الحفظ
            if (sheet.usableRemnants.isNotEmpty) ...[
              Row(
                children: [
                  const Icon(Icons.bookmark_add_outlined, size: 18, color: Colors.orange),
                  const SizedBox(width: 6),
                  Text(
                    '${isArabic ? 'فضلات صالحة للاستعمال ناتجة:' : 'Chutes réutilisables:'} (${sheet.usableRemnants.length})',
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5),
                  ),
                  const Spacer(),
                  FilledButton.tonalIcon(
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      visualDensity: VisualDensity.compact,
                    ),
                    icon: const Icon(Icons.save_alt, size: 16),
                    label: Text(
                      isArabic ? 'حفظ الفضلات بالمخزون' : 'Stocker chutes',
                      style: const TextStyle(fontSize: 11.5),
                    ),
                    onPressed: () => _saveGeneratedRemnantsToInventory(sheet),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 8,
                runSpacing: 4,
                children: sheet.usableRemnants.map((rem) {
                  return Chip(
                    visualDensity: VisualDensity.compact,
                    backgroundColor: Colors.teal.shade50,
                    side: BorderSide(color: Colors.teal.shade200),
                    label: Text(
                      '${rem.length.round()} × ${rem.width.round()} مم (${rem.areaSqm.toStringAsFixed(2)} m²)',
                      style: TextStyle(
                        fontSize: 11,
                        color: Colors.teal.shade900,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  );
                }).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// رسم تخطيطي بصري للوح ثنائي الأبعاد بمقياس رسم متناسب
  Widget _buildVisualSheetCanvas(OptimizedSheet sheet) {
    const canvasHeight = 180.0;
    final aspectRatio = sheet.sheetWidthMm > 0 ? sheet.sheetLengthMm / sheet.sheetWidthMm : 1.5;
    final canvasWidth = (canvasHeight * aspectRatio).clamp(240.0, 500.0);

    return Center(
      child: Container(
        height: canvasHeight,
        width: canvasWidth,
        decoration: BoxDecoration(
          color: Colors.grey.shade200,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade400, width: 1.5),
        ),
        child: CustomPaint(
          size: Size(canvasWidth, canvasHeight),
          painter: _SheetDiagramPainter(sheet: sheet),
        ),
      ),
    );
  }
}

/// فنان الرسم البصري للألواح والقطع المقصوصة
class _SheetDiagramPainter extends CustomPainter {
  final OptimizedSheet sheet;

  _SheetDiagramPainter({required this.sheet});

  @override
  void paint(Canvas canvas, Size size) {
    if (sheet.sheetLengthMm <= 0 || sheet.sheetWidthMm <= 0) return;

    final scaleX = size.width / sheet.sheetLengthMm;
    final scaleY = size.height / sheet.sheetWidthMm;

    // 1. رسم الفضلات الصالحة للاستعمال (لون أخضر مائل للشفافية)
    final remPaint = Paint()
      ..color = Colors.teal.withValues(alpha: 0.25)
      ..style = PaintingStyle.fill;
    final remBorder = Paint()
      ..color = Colors.teal.shade400
      ..strokeWidth = 1.0
      ..style = PaintingStyle.stroke;

    for (final rem in sheet.usableRemnants) {
      final rect = Rect.fromLTWH(
        rem.y * scaleX,
        rem.x * scaleY,
        rem.length * scaleX,
        rem.width * scaleY,
      );
      canvas.drawRect(rect, remPaint);
      canvas.drawRect(rect, remBorder);
    }

    // 2. رسم القطع المقصوصة (أزرق فاتح مع حدود زرقاء داكنة)
    final cutPaint = Paint()
      ..color = Colors.blue.shade100
      ..style = PaintingStyle.fill;
    final cutBorder = Paint()
      ..color = Colors.blue.shade700
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;

    final textStyle = const TextStyle(
      color: Colors.blueGrey,
      fontSize: 9,
      fontWeight: FontWeight.bold,
    );

    for (final cut in sheet.cuts) {
      final rect = Rect.fromLTWH(
        cut.y * scaleX,
        cut.x * scaleY,
        cut.cutLength * scaleX,
        cut.cutWidth * scaleY,
      );
      canvas.drawRect(rect, cutPaint);
      canvas.drawRect(rect, cutBorder);

      // رسم الأبعاد واسم القطعة إذا كانت المساحة تسمح
      if (rect.width > 30 && rect.height > 18) {
        final span = TextSpan(
          text: '${cut.cutLength.round()}×${cut.cutWidth.round()}',
          style: textStyle,
        );
        final tp = TextPainter(
          text: span,
          textDirection: TextDirection.ltr,
        )..layout(maxWidth: rect.width);
        tp.paint(
          canvas,
          Offset(rect.left + (rect.width - tp.width) / 2, rect.top + (rect.height - tp.height) / 2),
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _SheetDiagramPainter oldDelegate) => true;
}
