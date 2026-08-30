import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:database_data/settings/app_settings.dart';
import 'package:database_data/settings/localization.dart';

enum GlassWorkType {
  showerCabin,
  vitrineSingleDoor,
  vitrineDoubleDoor,
  slidingShowerCabin,
  singleDoorShowerCabin,
}

class TemperedGlassWorkScreen extends StatefulWidget {
  const TemperedGlassWorkScreen({super.key, this.initialPayload});

  // Kept so existing navigation calls continue to compile. The new drawing
  // starts empty and deliberately does not restore an old glass-work payload.
  final Map<String, dynamic>? initialPayload;

  @override
  State<TemperedGlassWorkScreen> createState() =>
      _TemperedGlassWorkScreenState();
}

class _TemperedGlassWorkScreenState extends State<TemperedGlassWorkScreen> {
  GlassWorkType _workType = GlassWorkType.vitrineSingleDoor;
  final _widthController = TextEditingController();
  final _heightController = TextEditingController();
  final List<Rect> _panels = [];
  Offset? _drawStart;
  Rect? _draftPanel;

  String _tr(String ar, String fr, String en) {
    final language = Provider.of<AppSettingsProvider>(
      context,
      listen: false,
    ).language;
    final translated = Localization.translate(ar, language);
    if (language == AppLanguage.arabic || translated != ar) return translated;
    return switch (language) {
      AppLanguage.french => fr,
      AppLanguage.english => en,
      AppLanguage.arabic => ar,
    };
  }

  String _workTypeLabel(GlassWorkType type) {
    return switch (type) {
      GlassWorkType.showerCabin =>
        _tr('كابين دوش', 'Cabine de douche', 'Shower cabin'),
      GlassWorkType.vitrineSingleDoor =>
        _tr('فيترين بباب واحد', 'Vitrine à une porte', 'One-door storefront'),
      GlassWorkType.vitrineDoubleDoor =>
        _tr('فيترين ببابين', 'Vitrine à deux portes', 'Two-door storefront'),
      GlassWorkType.slidingShowerCabin => _tr(
        'كابين دوش منزلقة',
        'Cabine de douche coulissante',
        'Sliding shower cabin',
      ),
      GlassWorkType.singleDoorShowerCabin => _tr(
        'كابين دوش بباب واحد',
        'Cabine de douche à une porte',
        'One-door shower cabin',
      ),
    };
  }

  @override
  void dispose() {
    _widthController.dispose();
    _heightController.dispose();
    super.dispose();
  }

  void _startPanel(DragStartDetails details) {
    _drawStart = details.localPosition;
    setState(() => _draftPanel = Rect.fromPoints(_drawStart!, _drawStart!));
  }

  void _resizePanel(DragUpdateDetails details) {
    final start = _drawStart;
    if (start == null) return;
    setState(() => _draftPanel = Rect.fromPoints(start, details.localPosition));
  }

  void _finishPanel(DragEndDetails details) {
    final panel = _draftPanel;
    _drawStart = null;
    if (panel == null || panel.width < 12 || panel.height < 12) {
      setState(() => _draftPanel = null);
      return;
    }
    setState(() {
      _panels.add(panel);
      _draftPanel = null;
    });
  }

  void _calculateQuantityAndCost() {
    if (_panels.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'ارسم في مساحة الرسم أولاً.',
              'Dessinez d’abord dans la zone de dessin.',
              'Draw in the canvas first.',
            ),
          ),
        ),
      );
      return;
    }

    final width = double.tryParse(
      _widthController.text.trim().replaceAll(',', '.'),
    );
    final height = double.tryParse(
      _heightController.text.trim().replaceAll(',', '.'),
    );
    if (width == null || height == null || width <= 0 || height <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _tr(
              'أدخل الطول والعرض بشكل صحيح.',
              'Saisissez correctement la hauteur et la largeur.',
              'Enter a valid width and height.',
            ),
          ),
        ),
      );
      return;
    }

    final area = (width / 1000) * (height / 1000);

    Navigator.pop(context, <String, dynamic>{
      'type': 'tempered_glass_work',
      'workType': _workType.name,
      'workTypeLabel': _workTypeLabel(_workType),
      'widthMm': width,
      'heightMm': height,
      'drawingVersion': 1,
      'drawingPanels': _panels
          .map(
            (panel) => {
              'left': panel.left,
              'top': panel.top,
              'width': panel.width,
              'height': panel.height,
            },
          )
          .toList(),
      'items': [
        {
          'id': 'glass_panel_${DateTime.now().microsecondsSinceEpoch}',
          'widthMm': width,
          'heightMm': height,
          'quantity': 1,
          'areaSqm': area,
          'pricePerSqm': 0.0,
          'unitPrice': 0.0,
          'totalPrice': 0.0,
        },
      ],
      'itemsCount': 1,
      'totalQuantity': 1,
      'grandTotalAreaSqm': area,
      'grandTotalPrice': 0.0,
    });
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    const workTypes = [
      GlassWorkType.showerCabin,
      GlassWorkType.vitrineSingleDoor,
      GlassWorkType.vitrineDoubleDoor,
      GlassWorkType.slidingShowerCabin,
      GlassWorkType.singleDoorShowerCabin,
    ];

    return Scaffold(
      appBar: AppBar(
        title: Text(_tr('رسم الزجاج', 'Dessin du verre', 'Glass drawing')),
        backgroundColor: Colors.cyan.shade800,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<GlassWorkType>(
                      initialValue: _workType,
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _tr(
                          'نوع العمل',
                          'Type de travail',
                          'Work type',
                        ),
                        border: const OutlineInputBorder(),
                      ),
                      items: workTypes
                          .map(
                            (type) => DropdownMenuItem(
                              value: type,
                              child: Text(
                                _workTypeLabel(type),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: (value) {
                        if (value != null) setState(() => _workType = value);
                      },
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _widthController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _tr('العرض', 'Largeur', 'Width'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _heightController,
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        isDense: true,
                        labelText: _tr('الطول', 'Hauteur', 'Height'),
                        suffixText: 'mm',
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: isDark ? Colors.blueGrey.shade900 : Colors.white,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isDark
                          ? Colors.cyan.shade700
                          : Colors.blue.shade200,
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onPanStart: _startPanel,
                    onPanUpdate: _resizePanel,
                    onPanEnd: _finishPanel,
                    child: CustomPaint(
                      painter: _GlassPanelDrawingPainter(
                        panels: _panels,
                        draftPanel: _draftPanel,
                        color: isDark
                            ? Colors.cyan.shade200
                            : Colors.cyan.shade800,
                      ),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _calculateQuantityAndCost,
                  icon: const Icon(Icons.calculate_outlined),
                  label: Text(
                    _tr(
                      'حساب الكمية والتكلفة',
                      'Calculer quantité et coût',
                      'Calculate quantity and cost',
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GlassPanelDrawingPainter extends CustomPainter {
  const _GlassPanelDrawingPainter({
    required this.panels,
    required this.draftPanel,
    required this.color,
  });

  final List<Rect> panels;
  final Rect? draftPanel;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final glassPaint = Paint()
      ..color = const Color(0xFFB9E5F8).withValues(alpha: 0.82)
      ..style = PaintingStyle.fill;
    final glassBorderPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final reflectionPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.60)
      ..strokeWidth = 5
      ..strokeCap = StrokeCap.round;

    final allPanels = [...panels, if (draftPanel != null) draftPanel!];
    for (final panel in allPanels) {
      if (panel.width < 2 || panel.height < 2) continue;
      final shortSide = panel.width < panel.height ? panel.width : panel.height;
      final inset = (shortSide * 0.04).clamp(2.0, 6.0);
      final glassRect = panel.deflate(inset);

      canvas.drawRect(glassRect, glassPaint);
      canvas.drawRect(glassRect, glassBorderPaint);
      canvas.drawLine(
        Offset(
          glassRect.left + glassRect.width * 0.18,
          glassRect.top + glassRect.height * 0.16,
        ),
        Offset(
          glassRect.left + glassRect.width * 0.32,
          glassRect.top + glassRect.height * 0.40,
        ),
        reflectionPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _GlassPanelDrawingPainter oldDelegate) => true;
}
